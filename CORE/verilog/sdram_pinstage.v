//
// sdram_pinstage.v
//
// For the simulations: what sdram_m65.v does for falcon_sdram.v in the core.
// It initializes the SDRAM like sdram_m65.v (>200 us, PRECHARGE ALL, AUTO
// REFRESH, LOAD MODE 0x222: BL=4 reads, single writes, CL=2), then raises
// ext_ready and passes the controller's signals through one register stage
// (the IOB registers of sdram_m65.v) to the pins. SDRAM clock: inverted clk_96.
//
// MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3

module sdram_pinstage (
	input             init,
	input             clk_96,
	output reg        ext_ready = 1'b0,

	input       [3:0] ext_cmd,
	input      [12:0] ext_addr,
	input       [1:0] ext_ba,
	input       [1:0] ext_dqm,
	input      [15:0] ext_dout,
	input             ext_doe,
	output reg [15:0] ext_din,

	inout      [15:0] sd_data,
	output reg [12:0] sd_addr,
	output reg  [1:0] sd_dqm,
	output reg  [1:0] sd_ba,
	output            sd_cs,
	output            sd_we,
	output            sd_ras,
	output            sd_cas,
	output            sd_clk
);

localparam CMD_NOP = 4'b0111, CMD_PRECHARGE = 4'b0010, CMD_AUTO_REFRESH = 4'b0001, CMD_LOAD_MODE = 4'b0000;

reg   [3:0] sd_cmd = CMD_NOP;
reg  [15:0] sd_dout;
reg         sd_doe = 1'b0;
reg  [14:0] init_cnt = 15'd0;

assign {sd_cs, sd_ras, sd_cas, sd_we} = sd_cmd;
assign sd_data = sd_doe ? sd_dout : 16'bz;

always @(posedge clk_96) begin
	ext_din <= sd_data;
	if (init) begin
		init_cnt  <= 15'd0;
		ext_ready <= 1'b0;
		sd_cmd    <= CMD_NOP;
		sd_doe    <= 1'b0;
	end
	else if (!ext_ready) begin
		init_cnt <= init_cnt + 15'd1;
		sd_cmd   <= CMD_NOP;
		sd_doe   <= 1'b0;
		sd_dqm   <= 2'b00;
		sd_ba    <= 2'b00;
		sd_addr  <= 13'b0010000000000;
		case (init_cnt)
			15'd20000: sd_cmd <= CMD_PRECHARGE;
			15'd20004, 15'd20012, 15'd20020, 15'd20028: sd_cmd <= CMD_AUTO_REFRESH;
			15'd20036: begin sd_cmd <= CMD_LOAD_MODE; sd_addr <= 13'h222; end
			15'd20040: ext_ready <= 1'b1;
			default: ;
		endcase
	end
	else begin
		sd_cmd  <= ext_cmd;
		sd_addr <= ext_addr;
		sd_ba   <= ext_ba;
		sd_dqm  <= ext_dqm;
		sd_dout <= ext_dout;
		sd_doe  <= ext_doe;
	end
end

ODDR #(
	.DDR_CLK_EDGE("SAME_EDGE"),
	.INIT(1'b0),
	.SRTYPE("SYNC")
) sdramclk_ddr (
	.Q(sd_clk), .C(clk_96), .CE(1'b1), .D1(1'b0), .D2(1'b1), .R(1'b0), .S(1'b0)
);

endmodule
