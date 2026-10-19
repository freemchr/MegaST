// WD1772 for a real floppy drive: WF1772IP (CORE/vhdl/floppy/wf1772ip, converted to a clock enable)
// behind the CPU interface of the MiSTer fdc1772.sv (cpu_sel/addr/rw/din/dout, irq, drq).
//
// * The IP runs on clk_32 with a clock enable at half rate (its 16 MHz timing).
// * The IP samples its bus only on enabled edges. The DMA chip selects the FDC for a data byte only
//   until the next 8 MHz enable (dma.v, fdc_dma_sel), which can be a single clk_32 cycle, so a select
//   is stretched by 3 cycles with the address, direction and data held: every access spans at least
//   two enabled edges. Read data is a combinational multiplexer in the IP, valid during the select.
// * Drive side: all signals active high; rdata is the filtered RDATA level from m65_floppy_port.vhd.
// * Read retry (retry = 1, menu "Floppy read assist"): a "read sector" command (single sector) is run with
//   the data going into a buffer instead of the DMA. On a CRC error the command is repeated in the IP (up to
//   RETRIES more revolutions); then the buffered bytes go to the DMA (one every 8 us) and INTRQ follows with
//   the status of the last attempt. A drive that misreads now and then therefore delivers good data, and
//   the ST never sees the wrong bytes of a failed attempt (some loaders do not survive them: Jim Power keeps
//   them and hangs). A sector that never reads still ends with the CRC error, just later. While the command
//   runs, the CPU reads the shadow registers and a busy status, and like a busy WD1772 the controller ignores
//   everything else but "force interrupt" (a loader that times out and writes the read command again just
//   waits on).
// * Absent drive (absent = 1: drive B: is selected, which is not connected when the internal drive is A:):
//   a type I command (restore, seek, step) ends at once with the status the WD1772 gets on a drive that
//   is not there: a restore or a verify ends with a seek error, track 0 is never reported. The WD1772 would
//   step for 255 x 6 ms at TOS's step rate, longer than the 1.5 s timeout of TOS. TOS 2.06 sends drive B
//   7 restore and seek commands at every reset, so the reset took up to 10 s longer. The result for TOS
//   (no drive B) stays the same. Other commands go to
//   the IP as before (an own access, like a "force interrupt" during a buffered read).
//
// This machine is based on AtariST_MiSTer
// Powered by MiSTer2MEGA65
// MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3

module wd1772_m65 (
	input        clk_32,
	input        reset,

	input        cpu_sel,
	input  [1:0] cpu_addr,
	input        cpu_rw,
	input  [7:0] cpu_din,
	output [7:0] cpu_dout,
	output       irq,
	output       drq,

	output       motor,
	output       step,
	output       dir_in,       // 1 = step in (towards higher tracks)
	output       wgate,
	output       wdata,
	input        rdata,
	input        index,
	input        track0,
	input        wprot,
	input        side,         // 1 = side 1 (only for the command log)
	input        retry,        // 1 = repeat failed sector reads internally (see above)
	input        absent,       // 1 = the selected drive is not connected (see above)

	// debugging (JTAG probe in mega65.vhd): log of the last 256 commands, entry dbg_idx, see below
	input  [7:0] dbg_idx,
	output [55:0] dbg_entry,
	output [15:0] dbg_count     // number of commands logged so far
);

localparam RETRIES = 4'd15;            // extra attempts after a CRC error (one revolution each)
localparam M_IDLE = 2'd0, M_CAP = 2'd1, M_DLV = 2'd2;

reg       ce = 1'b0;
reg [1:0] hold = 2'd0;
reg [1:0] addr_l;
reg       rw_l;
reg [7:0] din_l;
reg [1:0] mode = M_IDLE;
// shadows of the IP's registers (the command log and the CPU during a buffered read)
reg   [7:0] sh_trk = 8'd0, sh_data = 8'd0, sh_sec = 8'd0, sh_cmd = 8'd0;
reg   [9:0] sh_dma = 10'd0;
reg         sh_side = 1'b0, sh_dir_in = 1'b1;
reg         sel_d = 1'b0, sel_dd = 1'b0, irq_d = 1'b0;

// CPU accesses that start outside a buffered read reach the IP (to their end, also when the read starts with
// them). During a buffered read the controller is busy: like the WD1772 it ignores commands other than
// "force interrupt", which ends the buffered read and goes to the IP as an own access (fi_pend). The
// forwarding is not decoded from cpu_din: the DMA chip routes cpu_dout back to cpu_din (combinational loop).
reg  fwd_l     = 1'b0;
reg  fi_pend   = 1'b0;
reg  [7:0] fi_cmd;
wire cmd_wr    = cpu_sel & ~cpu_rw & cpu_addr == 2'd0;
wire cpu_fwd   = cpu_sel & (sel_d ? fwd_l : mode == M_IDLE & ~(absent & cmd_wr));
// a command to an absent drive (not forwarded): a type I command is answered here (ab_st), others are
// written to the IP by an own access (fi_pend)
wire ab_wr     = cmd_wr & ~sel_d & absent & mode == M_IDLE;
reg  ab_valid  = 1'b0;                 // the status register shows ab_st
reg  ab_go     = 1'b0;                 // INTRQ at the end of the CPU's write
reg  ab_irq    = 1'b0;
reg  [7:0] ab_st;

// the buffered read's own accesses to the IP (same timing as a CPU access: 4 cycles)
reg       acc_go = 1'b0;               // start an access (one cycle)
reg       acc_rw;
reg [1:0] acc_addr;
reg [7:0] acc_din;
reg [2:0] acc_cnt = 3'd0;
wire      acc_cs = acc_cnt != 3'd0;
wire      acc_end = acc_cnt == 3'd1;

always @(posedge clk_32) begin
	ce <= ~ce;
	fwd_l <= cpu_fwd;
	if (cpu_fwd) begin
		hold   <= 2'd3;
		addr_l <= cpu_addr;
		rw_l   <= cpu_rw;
		din_l  <= cpu_din;
	end else if (hold != 2'd0)
		hold <= hold - 2'd1;
	if (cpu_fwd | reset)
		acc_cnt <= 3'd0;                 // the CPU's access wins
	else if (acc_go)
		acc_cnt <= 3'd4;
	else if (acc_cs)
		acc_cnt <= acc_cnt - 3'd1;
end

wire       cs   = cpu_fwd | (hold != 2'd0) | acc_cs;
wire [1:0] addr = cpu_fwd ? cpu_addr : hold != 2'd0 ? addr_l : acc_addr;
wire       rw   = cpu_fwd ? cpu_rw   : hold != 2'd0 ? rw_l   : acc_rw;
wire [7:0] din  = cpu_fwd ? cpu_din  : hold != 2'd0 ? din_l  : acc_din;
wire [7:0] ip_dout;
wire       ip_irq, ip_drq;

WF1772IP_TOP_SOC fdc (
	.CLK      ( clk_32    ),
	.CE       ( ce        ),
	.RESETn   ( ~reset    ),
	.CSn      ( ~cs       ),
	.RWn      ( rw        ),
	.A1       ( addr[1]   ),
	.A0       ( addr[0]   ),
	.DATA_IN  ( din       ),
	.DATA_OUT ( ip_dout   ),
	.DATA_EN  (           ),
	.RDn      ( ~rdata    ),
	.TR00n    ( ~track0   ),
	.IPn      ( ~index    ),
	.WPRTn    ( ~wprot    ),
	.DDEn     ( 1'b0      ),   // MFM (double density)
	.HDTYPE   ( 1'b0      ),   // DD timing
	.MO       ( motor     ),
	.WG       ( wgate     ),
	.WD       ( wdata     ),
	.STEP     ( step      ),
	.DIRC     ( dir_in    ),
	.DRQ      ( ip_drq    ),
	.INTRQ    ( ip_irq    )
);

// Buffered read with retries
reg  [7:0] buf_mem [0:1023];
reg  [7:0] buf_q;
reg [10:0] cap_n = 11'd0;              // bytes captured in the current attempt
reg [10:0] dlv_n = 11'd0;              // bytes delivered to the DMA
reg  [3:0] tries_left = 4'd0;
reg  [7:0] cmd_l;                      // the read command
reg  [7:0] st_l;                       // status of the last attempt
reg        st_drq = 1'b0, st_irq = 1'b0;
reg        ip_irq_d = 1'b0, ip_done = 1'b0;
reg  [1:0] acc_kind = 2'd0;            // 0 data byte, 1 status, 2 command
reg  [2:0] cool = 3'd0;                // after reading a byte: wait until the IP has dropped DRQ
reg  [7:0] pace = 8'd0;
reg        pop = 1'b0;
reg        buffered = 1'b0;               // the last command was a buffered read (command log)

wire start_read = retry & cmd_wr & ~sel_d & cpu_din[7:4] == 4'h8 & mode == M_IDLE;
wire cpu_rd     = cpu_sel & ~sel_d & cpu_rw;
wire bus_free   = hold == 2'd0 & ~acc_cs & ~acc_go;

always @(posedge clk_32) buf_q <= buf_mem[dlv_n[9:0]];

always @(posedge clk_32) begin
	acc_go   <= 1'b0;
	ip_irq_d <= ip_irq;
	if (cool != 3'd0) cool <= cool - 3'd1;
	if (ip_irq & ~ip_irq_d) ip_done <= 1'b1;
	// the CPU clears INTRQ by reading the status or writing a command
	if (cpu_sel & cpu_addr == 2'd0) begin st_irq <= 1'b0; ab_irq <= 1'b0; end

	// absent drive: a type I command ends at once (status: motor, spin-up done, seek error after a restore
	// or a verify); the status stays until the next command reaches the IP
	if (ab_wr & ~cpu_din[7]) begin
		ab_valid <= 1'b1;
		ab_go    <= 1'b1;
		ab_st    <= { motor, 2'b01, cpu_din[7:4] == 4'h0 | cpu_din[2], 4'b0000 };
	end else if (ab_wr) begin
		fi_pend  <= 1'b1;
		fi_cmd   <= cpu_din;
	end
	if (ab_go & ~cpu_sel) begin
		ab_go    <= 1'b0;
		ab_irq   <= 1'b1;
	end
	if ((cpu_fwd & cmd_wr) | (acc_go & ~acc_rw & acc_addr == 2'd0)) ab_valid <= 1'b0;

	case (mode)
	M_IDLE: begin
		if (cpu_fwd & ~sel_d & ~cpu_rw & cpu_addr == 2'd0) begin
			tries_left <= RETRIES;                                    // the log shows 0 retries
			buffered   <= start_read;
		end
		if (start_read) begin
			mode       <= M_CAP;
			cmd_l      <= cpu_din;
			cap_n      <= 11'd0;
			ip_done    <= 1'b0;
		end
	end
	M_CAP:
		if (bus_free & cool == 3'd0) begin
			if (ip_drq) begin                                      // a data byte
				acc_go <= 1'b1; acc_rw <= 1'b1; acc_addr <= 2'd3; acc_kind <= 2'd0;
			end else if (ip_done) begin                            // the attempt has ended: read the status
				acc_go <= 1'b1; acc_rw <= 1'b1; acc_addr <= 2'd0; acc_kind <= 2'd1;
				ip_done <= 1'b0;
			end
		end
	M_DLV: begin
		if (pace != 8'd0) pace <= pace - 8'd1;
		if (cpu_rd & cpu_addr == 2'd3 & st_drq) begin
			st_drq <= 1'b0;
			pop    <= 1'b1;
		end
		if (pop & ~cpu_sel) begin
			pop   <= 1'b0;
			dlv_n <= dlv_n + 11'd1;
			pace  <= 8'd255;                                      // 8 us per byte
		end else if (~st_drq & ~pop & pace == 8'd0) begin
			if (dlv_n != cap_n)
				st_drq <= 1'b1;
			else begin
				mode   <= M_IDLE;                                    // all delivered: end of the command
				st_irq <= 1'b1;
			end
		end
	end
	default: mode <= M_IDLE;
	endcase

	// the end of an own access: the IP's read data is valid in its last cycle
	if (acc_end & mode == M_CAP) case (acc_kind)
		2'd0: begin
			if (~cap_n[10]) begin
				buf_mem[cap_n[9:0]] <= ip_dout;
				cap_n <= cap_n + 11'd1;
			end
			cool <= 3'd4;
		end
		2'd1:
			if (ip_dout[3] & tries_left != 4'd0) begin             // CRC error: once more
				tries_left <= tries_left - 4'd1;
				cap_n    <= 11'd0;
				acc_go   <= 1'b1; acc_rw <= 1'b0; acc_addr <= 2'd0; acc_kind <= 2'd2;
				acc_din  <= cmd_l & 8'hFB;                          // without the 15 ms settling delay
			end else begin
				st_l   <= ip_dout;
				mode   <= M_DLV;
				dlv_n  <= 11'd0;
				pace   <= 8'd255;
			end
		default: ;
	endcase

	// "force interrupt" during a buffered read: end it, then write the command to the IP (bus free)
	if (fi_pend & bus_free & ~cpu_fwd) begin
		fi_pend <= 1'b0;
		acc_go  <= 1'b1; acc_rw <= 1'b0; acc_addr <= 2'd0; acc_kind <= 2'd2; acc_din <= fi_cmd;
	end
	if ((cmd_wr & ~sel_d & mode != M_IDLE & cpu_din[7:4] == 4'hD) | reset) begin
		mode     <= M_IDLE;
		st_drq   <= 1'b0;
		st_irq   <= 1'b0;
		pop      <= 1'b0;
		buffered <= 1'b0;
		fi_pend  <= ~reset;
		fi_cmd   <= cpu_din;
	end
	if (reset) begin
		ab_valid <= 1'b0;
		ab_go    <= 1'b0;
		ab_irq   <= 1'b0;
	end
end

// the CPU side: during a buffered read the shim answers, otherwise the IP
reg [7:0] shim_dout;
always @(*) case (cpu_addr)
	2'd0:    shim_dout = mode == M_DLV ? { st_l[7:2], st_drq, 1'b1 } : { motor, 6'b010000, 1'b1 };
	2'd1:    shim_dout = sh_trk;
	2'd2:    shim_dout = sh_sec;
	default: shim_dout = mode == M_DLV ? buf_q : sh_data;
endcase
assign cpu_dout = mode == M_IDLE ? (ab_valid & cpu_addr == 2'd0 ? ab_st : ip_dout) : shim_dout;
assign drq      = mode == M_IDLE ? ip_drq : st_drq;
assign irq      = mode == M_IDLE ? ip_irq | st_irq | ab_irq : 1'b0;

// Command log for the JTAG probe. An entry is written when a command ends (INTRQ) and updated with the
// first status the CPU reads after it. Entry bits: 7..0 command, 15..8 track (shadow of the track
// register at the start), 23..16 data register, 31..24 sector register, 39..32 status read by the CPU
// (FF: none yet), 49..40 bytes read by DMA, 50 side, 51 buffered read, 55..52 its retries.
reg  [55:0] log_mem [0:255];
reg  [15:0] log_cnt = 16'd0;
reg  [55:0] log_cur;
reg   [7:0] log_last;
reg         log_wait = 1'b0;

assign dbg_entry = log_mem[dbg_idx];
assign dbg_count = log_cnt;

// one write port: a new entry at the end of a command, or the status of the last entry
wire        log_new  = irq & ~irq_d & ~reset;
wire        log_st   = sel_d & ~sel_dd & rw_l & addr_l == 2'd0 & log_wait & ~reset;
wire [55:0] log_ent  = { RETRIES - tries_left, buffered, sh_side, sh_dma, 8'hFF, sh_sec, sh_data, sh_trk, sh_cmd };

always @(posedge clk_32)
	if (log_new)     log_mem[log_cnt[7:0]] <= log_ent;
	else if (log_st) log_mem[log_last]     <= { log_cur[55:40], cpu_dout, log_cur[31:0] };

always @(posedge clk_32) begin
	sel_d  <= cpu_sel;
	sel_dd <= sel_d;
	irq_d  <= irq;
	if (reset) begin
		log_wait <= 1'b0;
	end else begin
		// CPU and DMA accesses: the IP keeps address and data for 3 cycles (hold), read data one cycle later
		if (cpu_sel & ~sel_d & ~cpu_rw & (mode == M_IDLE | cpu_addr == 2'd0 & cpu_din[7:4] == 4'hD)) case (cpu_addr)
			2'd0: begin sh_cmd <= cpu_din; sh_dma <= 10'd0; sh_side <= side; log_wait <= 1'b0;
			            if (cpu_din[7:5] == 3'b010) sh_dir_in <= 1'b1;        // step in
			            if (cpu_din[7:5] == 3'b011) sh_dir_in <= 1'b0;        // step out
			      end
			2'd1: sh_trk  <= cpu_din;
			2'd2: sh_sec  <= cpu_din;
			2'd3: sh_data <= cpu_din;
		endcase
		if (cpu_sel & ~sel_d & cpu_rw & cpu_addr == 2'd3 & ~&sh_dma) sh_dma <= sh_dma + 10'd1;
		if (log_st) log_wait <= 1'b0;
		// end of a command: log it, then update the track shadow like the WD1772 does
		if (log_new) begin
			log_cur  <= log_ent;
			log_last <= log_cnt[7:0];
			log_cnt  <= log_cnt + 16'd1;
			log_wait <= 1'b1;
			if (sh_cmd[7:4] == 4'h0) sh_trk <= 8'd0;                       // restore
			else if (sh_cmd[7:4] == 4'h1) sh_trk <= sh_data;               // seek
			else if (~sh_cmd[7] & sh_cmd[4]) begin                         // step with update
				if (sh_cmd[7:5] == 3'b010 || (sh_cmd[7:5] == 3'b001 && sh_dir_in)) sh_trk <= sh_trk + 8'd1;
				else sh_trk <= sh_trk - 8'd1;
			end
		end
	end
end

endmodule
