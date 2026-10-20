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
// commands back to back (no gap in the data). The mode register is the same as
// in sdram_m65.v (BL=4 reads, single writes), so the ST and the Falcon can take
// turns without reprogramming it: a 64-bit write is four WRITE commands in a
// row, one per beat, each with its byte masks. Every access opens its row and
// closes it with auto precharge, so all banks are idle between commands and a
// refresh can always go in. Address: 64-bit word address a[20:0] (16 MB):
// column {a[7:0], 2'b00}, bank a[9:8], row a[20:10].
//
// Clocks: the Falcon side runs at clk_32, the SDRAM at clk_96 (same MMCM,
// rising edges aligned).
//
// No pins here: the SDRAM pins of the core belong to sdram_m65.v (the ST). In
// the Falcon mode its pin registers (in the IOBs) load the sd_*_o signals of
// this module instead of its own, and sd_din_i is its input register. So the
// commands reach the pins one clk_96 cycle later than in sdram_m65.v, and beat
// 0 of a READ is in sd_din_i 5 cycles after this module issued it. Pin timing,
// SDRAM clock and the initialization (start_i: sdram_m65.v has initialized the
// SDRAM) are those of sdram_m65.v, tested on the hardware. falcon_sdram_pins.v
// adds the same register stage and the pins for the simulations.
//
// MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3

module falcon_sdram (
	input             start_i,    // 1: the SDRAM is initialized and this controller owns it
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

	// SDRAM, through the pin registers of sdram_m65.v
	output reg  [3:0] sd_cmd_o,   // {CS#, RAS#, CAS#, WE#}
	output reg [12:0] sd_addr_o,
	output reg  [1:0] sd_ba_o,
	output reg  [1:0] sd_dqm_o,
	output reg [15:0] sd_dout_o,
	output reg        sd_doe_o,
	input      [15:0] sd_din_i    // the pin input register
);

localparam CMD_NOP          = 4'b0111;
localparam CMD_ACTIVE       = 4'b0011;
localparam CMD_READ         = 4'b0101;
localparam CMD_WRITE        = 4'b0100;
localparam CMD_AUTO_REFRESH = 4'b0001;

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
reg [63:0] s_buf[0:3];          // read words for the Falcon side (clk_96 writes)
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

localparam S_INIT = 3'd0, S_IDLE = 3'd1, S_ACT = 3'd2, S_READ = 3'd3, S_WRITE = 3'd4, S_WAIT = 3'd5;

reg  [2:0] st = S_INIT;
reg [14:0] init_cnt = 15'd0;
reg  [4:0] wait_cnt;            // cycles to wait in S_ACT / S_WAIT / S_READ (gap between READs)
reg  [9:0] ref_cnt;             // cycles since the last refresh
reg        s_tog = 1'b0;        // last command seen
reg  [1:0] word;                // word (READ) or beat (WRITE) of the command

// read data capture: beat 0 of a READ is in sd_din_i 5 cycles after the command
reg  [2:0] cap_delay = 3'd0;
reg  [4:0] cap_left = 5'd0;     // beats still to come
reg  [1:0] cap_beat;
reg [47:0] cap_sr;

wire [1:0] c_bank = c_addr[9:8];
wire       last = !c_four || word == 2'd3;   // the READ now is the last one
wire [12:0] c_row = {2'b00, c_addr[20:10]};

always @(posedge clk_96) begin
	sd_cmd_o <= CMD_NOP;
	sd_doe_o <= 1'b0;
	sd_dqm_o <= 2'b00;
	if (ref_cnt != 10'h3ff) ref_cnt <= ref_cnt + 10'd1;

	// collect the read beats into 64-bit words
	if (cap_delay != 0) cap_delay <= cap_delay - 3'd1;
	else if (cap_left != 0) begin
		cap_left <= cap_left - 5'd1;
		cap_beat <= cap_beat + 2'd1;
		cap_sr   <= {sd_din_i, cap_sr[47:16]};
		if (cap_beat == 2'd3) begin
			s_buf[s_wr[1:0]] <= {sd_din_i, cap_sr};
			s_wr <= s_wr + 3'd1;
		end
	end

	if (!start_i) begin
		st       <= S_INIT;
		init_cnt <= 15'd0;
		s_ready  <= 1'b0;
	end
	else case (st)
	// sdram_m65.v has initialized the SDRAM (same mode register); its last command may still run
	S_INIT: begin
		init_cnt <= init_cnt + 15'd1;
		if (init_cnt == 15'd15) begin st <= S_IDLE; s_ready <= 1'b1; ref_cnt <= 10'd0; end
	end

	S_IDLE:
		// refresh every 7.3 us (8192 rows in 64 ms: 7.8 us)
		if (ref_cnt >= 10'd700) begin
			sd_cmd_o   <= CMD_AUTO_REFRESH;
			ref_cnt  <= 10'd0;
			wait_cnt <= 5'd7;              // tRFC 60 ns
			st       <= S_WAIT;
		end
		else if (c_tog != s_tog) begin
			s_tog    <= c_tog;
			sd_cmd_o   <= CMD_ACTIVE;
			sd_ba_o    <= c_bank;
			sd_addr_o  <= c_row;
			word     <= 2'd0;
			wait_cnt <= 5'd0;              // READ/WRITE in the next but one cycle (tRCD 20 ns)
			st       <= S_ACT;
		end

	S_ACT:
		st <= c_we ? S_WRITE : S_READ;

	S_READ:
		if (wait_cnt != 0) wait_cnt <= wait_cnt - 5'd1;
		else begin
			sd_cmd_o  <= CMD_READ;
			sd_addr_o <= {2'b00, last, c_addr[7:2], c_four ? word : c_addr[1:0], 2'b00};   // A10: auto precharge
			if (word == 2'd0) begin
				cap_delay <= 3'd4;
				cap_left  <= c_four ? 5'd16 : 5'd4;
				cap_beat  <= 2'd0;
			end
			word     <= word + 2'd1;
			wait_cnt <= 5'd3;              // next READ 4 cycles later: no gap in the data
			if (last) begin
				wait_cnt <= 5'd9;          // last beat in sd_din_i after 8 cycles, precharge done after 7
				st       <= S_WAIT;
			end
		end

	S_WRITE: begin
		// four single WRITEs, the last one with auto precharge
		sd_cmd_o  <= CMD_WRITE;
		sd_addr_o <= {2'b00, word == 2'd3, c_addr[7:0], word};
		sd_dout_o <= c_din[16 * word +: 16];
		sd_doe_o  <= 1'b1;
		sd_dqm_o  <= ~c_be[2 * word +: 2];
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

endmodule
