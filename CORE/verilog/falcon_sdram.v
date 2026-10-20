//
// falcon_sdram.v
//
// The MiSTer DDRAM port of Falcon_MiSTer (falcon_memarb) on the MEGA65 SDRAM.
//
// The Falcon's memory arbiter talks to the MiSTer DDR3 through an Avalon port
// with 64-bit words: one command at a time, held until BUSY is low; a write is
// one word with byte enables, a read returns 1 or 4 words (DOUT_READY per word).
// 4-word reads are aligned to 32 bytes (Videl lines, CPU cache lines).
//
// The MEGA65 R4/R5/R6 SDRAM is an IS42S16320F (32M x 16). A 64-bit word is a
// burst of four 16-bit beats (BL=4) in one row, a 4-word read four READ
// commands back to back (no gap in the data). Every access opens its row and
// closes it with auto precharge, so all banks are idle between commands and a
// refresh can always go in. Address: 64-bit word address a[20:0] (16 MB):
// column {a[7:0], 2'b00}, bank a[9:8], row a[20:10].
//
// Clocks: the Falcon side runs at clk_32, the SDRAM at clk_96 (same MMCM,
// rising edges aligned). Pins, SDRAM clock (inverted clk_96 via ODDR), read
// latency and the initialization are the same as in sdram_m65.v, which is
// tested on the hardware.
//
// MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3

module falcon_sdram (
	input             init,       // FPGA configuration done: (re)initialize the SDRAM
	input             clk_32,
	input             clk_96,

	// MiSTer DDRAM port (clk_32)
	output            busy,
	input       [2:0] burstcnt,   // 1 or 4
	input      [20:0] addr,       // 64-bit word address
	output reg [63:0] dout,
	output reg        dout_ready,
	input             rd,
	input      [63:0] din,        // byte 0 = din[7:0] (lowest address of the little endian DDR3)
	input       [7:0] be,
	input             we,

	// SDRAM
	inout      [15:0] sd_data,
	(* IOB = "TRUE" *) output reg [12:0] sd_addr,
	(* IOB = "TRUE" *) output reg  [1:0] sd_dqm,
	(* IOB = "TRUE" *) output reg  [1:0] sd_ba,
	output            sd_cs,
	output            sd_we,
	output            sd_ras,
	output            sd_cas,
	output            sd_clk
);

localparam CAS_LATENCY = 3'd2;
localparam MODE        = {3'b000, 1'b0 /* write bursts */, 2'b00, CAS_LATENCY, 1'b0 /* sequential */, 3'b010 /* BL=4 */};

localparam CMD_NOP          = 4'b0111;
localparam CMD_ACTIVE       = 4'b0011;
localparam CMD_READ         = 4'b0101;
localparam CMD_WRITE        = 4'b0100;
localparam CMD_PRECHARGE    = 4'b0010;
localparam CMD_AUTO_REFRESH = 4'b0001;
localparam CMD_LOAD_MODE    = 4'b0000;

// ---------------------------------------------------------------------
// Falcon side (clk_32)
// ---------------------------------------------------------------------

reg        c_tog = 1'b0;        // toggles with every accepted command
reg        c_pend = 1'b0;       // a command is in the SDRAM controller
reg [20:0] c_addr;
reg        c_we;
reg        c_four;              // 4-word read
reg [63:0] c_din;
reg  [7:0] c_be;

reg        s_ready = 1'b0;      // SDRAM initialized (clk_96)
reg        s_done = 1'b0;       // toggles when a command is finished (clk_96)
reg [63:0] s_buf[0:3];            // read words for the Falcon side (clk_96 writes)
reg  [2:0] s_wr = 3'd0;         // words written into s_buf (clk_96)
reg  [2:0] c_rd = 3'd0;         // words given to the Falcon (clk_32)

assign busy = c_pend | ~s_ready;

always @(posedge clk_32) begin
	dout_ready <= 1'b0;
	if (c_pend && s_done == c_tog) c_pend <= 1'b0;
	if (!busy && (rd || we)) begin
		c_addr <= addr;
		c_we   <= we;
		c_four <= !we && burstcnt[2];
		c_din  <= din;
		c_be   <= be;
		c_tog  <= ~c_tog;
		c_pend <= 1'b1;
	end
	if (c_rd != s_wr) begin
		dout       <= s_buf[c_rd[1:0]];
		dout_ready <= 1'b1;
		c_rd       <= c_rd + 3'd1;
	end
end

// ---------------------------------------------------------------------
// SDRAM side (clk_96)
// ---------------------------------------------------------------------

(* IOB = "TRUE" *) reg [3:0]  sd_cmd = CMD_NOP;
(* IOB = "TRUE" *) reg [15:0] sd_dout;
(* IOB = "TRUE" *) reg [15:0] sd_doe;
(* IOB = "TRUE" *) reg [15:0] sd_din;

assign sd_cs  = sd_cmd[3];
assign sd_ras = sd_cmd[2];
assign sd_cas = sd_cmd[1];
assign sd_we  = sd_cmd[0];

genvar gi;
generate
	for (gi = 0; gi < 16; gi = gi + 1) begin : g_dq
		assign sd_data[gi] = sd_doe[gi] ? sd_dout[gi] : 1'bZ;
	end
endgenerate

localparam S_INIT = 3'd0, S_IDLE = 3'd1, S_ACT = 3'd2, S_READ = 3'd3, S_WRITE = 3'd4, S_WAIT = 3'd5;

reg  [2:0] st = S_INIT;
reg [14:0] init_cnt = 15'd0;
reg  [4:0] wait_cnt;            // cycles to wait in S_ACT / S_WAIT / S_READ (gap between READs)
reg  [9:0] ref_cnt;             // cycles since the last refresh
reg        s_tog = 1'b0;        // last command seen
reg  [1:0] word;                // word (READ) or beat (WRITE) of the command

// read data capture: beat 0 of a READ is in sd_din 4 cycles after the command
reg  [2:0] cap_delay = 3'd0;
reg  [4:0] cap_left = 5'd0;     // beats still to come
reg  [1:0] cap_beat;
reg [47:0] cap_sr;

wire [1:0] c_bank = c_addr[9:8];
wire       last = !c_four || word == 2'd3;   // the READ now is the last one
wire [12:0] c_row = {2'b00, c_addr[20:10]};

always @(posedge clk_96) begin
	sd_din <= sd_data;
	sd_cmd <= CMD_NOP;
	sd_doe <= 16'h0000;
	sd_dqm <= 2'b00;
	if (ref_cnt != 10'h3ff) ref_cnt <= ref_cnt + 10'd1;

	// collect the read beats into 64-bit words
	if (cap_delay != 0) cap_delay <= cap_delay - 3'd1;
	else if (cap_left != 0) begin
		cap_left <= cap_left - 5'd1;
		cap_beat <= cap_beat + 2'd1;
		cap_sr   <= {sd_din, cap_sr[47:16]};
		if (cap_beat == 2'd3) begin
			s_buf[s_wr[1:0]] <= {sd_din, cap_sr};
			s_wr <= s_wr + 3'd1;
		end
	end

	if (init) begin
		st       <= S_INIT;
		init_cnt <= 15'd0;
		s_ready  <= 1'b0;
	end
	else case (st)
	// >200 us stable clock, PRECHARGE ALL, 8 x AUTO REFRESH, LOAD MODE
	S_INIT: begin
		init_cnt <= init_cnt + 15'd1;
		sd_ba    <= 2'b00;
		sd_addr  <= 13'b0010000000000;  // A10: all banks
		case (init_cnt)
			15'd20000: sd_cmd <= CMD_PRECHARGE;
			15'd20004, 15'd20012, 15'd20020, 15'd20028,
			15'd20036, 15'd20044, 15'd20052, 15'd20060: sd_cmd <= CMD_AUTO_REFRESH;
			15'd20068: begin sd_cmd <= CMD_LOAD_MODE; sd_addr <= MODE; end
			15'd20072: begin st <= S_IDLE; s_ready <= 1'b1; ref_cnt <= 10'd0; end
			default: ;
		endcase
	end

	S_IDLE:
		// refresh every 7.3 us (8192 rows in 64 ms: 7.8 us)
		if (ref_cnt >= 10'd700) begin
			sd_cmd   <= CMD_AUTO_REFRESH;
			ref_cnt  <= 10'd0;
			wait_cnt <= 5'd7;              // tRFC 60 ns
			st       <= S_WAIT;
		end
		else if (c_tog != s_tog) begin
			s_tog    <= c_tog;
			sd_cmd   <= CMD_ACTIVE;
			sd_ba    <= c_bank;
			sd_addr  <= c_row;
			word     <= 2'd0;
			wait_cnt <= 5'd0;              // READ/WRITE in the next but one cycle (tRCD 20 ns)
			st       <= S_ACT;
		end

	S_ACT:
		st <= c_we ? S_WRITE : S_READ;

	S_READ:
		if (wait_cnt != 0) wait_cnt <= wait_cnt - 5'd1;
		else begin
			sd_cmd  <= CMD_READ;
			sd_addr <= {2'b00, last, c_addr[7:2], c_four ? word : c_addr[1:0], 2'b00};   // A10: auto precharge
			if (word == 2'd0) begin
				cap_delay <= 3'd3;
				cap_left  <= c_four ? 5'd16 : 5'd4;
				cap_beat  <= 2'd0;
			end
			word     <= word + 2'd1;
			wait_cnt <= 5'd3;              // next READ 4 cycles later: no gap in the data
			if (last) begin
				wait_cnt <= 5'd8;          // last beat in sd_din after 7 cycles, precharge done after 6
				st       <= S_WAIT;
			end
		end

	S_WRITE: begin
		// one WRITE, data and byte masks in the cycles of the burst
		if (word == 2'd0) begin
			sd_cmd  <= CMD_WRITE;
			sd_addr <= {2'b00, 1'b1, c_addr[7:0], 2'b00};   // auto precharge
		end
		sd_dout <= c_din[16 * word +: 16];
		sd_doe  <= 16'hFFFF;
		sd_dqm  <= ~c_be[2 * word +: 2];
		word    <= word + 2'd1;
		if (word == 2'd3) begin
			wait_cnt <= 5'd5;              // tWR 2 cycles, then tRP 20 ns
			st       <= S_WAIT;
		end
	end

	S_WAIT:
		if (wait_cnt != 0) wait_cnt <= wait_cnt - 5'd1;
		else begin
			if (s_done != s_tog) s_done <= s_tog;
			st <= S_IDLE;
		end

	default: st <= S_IDLE;
	endcase
end

// SDRAM clock = inverted clk_96 (as in sdram_m65.v)
ODDR #(
	.DDR_CLK_EDGE("SAME_EDGE"),
	.INIT(1'b0),
	.SRTYPE("SYNC")
) sdramclk_ddr (
	.Q(sd_clk),
	.C(clk_96),
	.CE(1'b1),
	.D1(1'b0),
	.D2(1'b1),
	.R(1'b0),
	.S(1'b0)
);

endmodule
