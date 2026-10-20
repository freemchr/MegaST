//
// falcon_sdram_pins.v
//
// falcon_sdram.v with SDRAM pins, for the simulations: what sdram_m65.v does for
// it in the core. It initializes the SDRAM like sdram_m65.v (>200 us, PRECHARGE
// ALL, AUTO REFRESH, LOAD MODE 0x222: BL=4 reads, single writes, CL=2), then
// starts falcon_sdram.v and passes its signals through one register stage (the
// IOB registers of sdram_m65.v) to the pins. SDRAM clock: inverted clk_96.
//
// MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3

module falcon_sdram_pins (
	input             init,
	input             clk_32,
	input             clk_96,

	output            busy,
	input       [2:0] burstcnt,
	input      [20:0] addr,
	output     [63:0] dout,
	output            dout_ready,
	input             rd,
	input      [63:0] din,
	input       [7:0] be,
	input             we,

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

wire  [3:0] f_cmd;
wire [12:0] f_addr;
wire  [1:0] f_ba, f_dqm;
wire [15:0] f_dout;
wire        f_doe;

reg   [3:0] sd_cmd = CMD_NOP;
reg  [15:0] sd_dout;
reg         sd_doe = 1'b0;
reg  [15:0] sd_din;
reg  [14:0] init_cnt = 15'd0;
reg         started = 1'b0;

assign {sd_cs, sd_ras, sd_cas, sd_we} = sd_cmd;
assign sd_data = sd_doe ? sd_dout : 16'bz;

falcon_sdram ctrl (
	.start_i(started), .clk_32(clk_32), .clk_96(clk_96),
	.busy(busy), .burstcnt(burstcnt), .addr(addr), .dout(dout), .dout_ready(dout_ready),
	.rd(rd), .din(din), .be(be), .we(we),
	.sd_cmd_o(f_cmd), .sd_addr_o(f_addr), .sd_ba_o(f_ba), .sd_dqm_o(f_dqm),
	.sd_dout_o(f_dout), .sd_doe_o(f_doe), .sd_din_i(sd_din)
);

always @(posedge clk_96) begin
	sd_din <= sd_data;
	if (init) begin
		init_cnt <= 15'd0;
		started  <= 1'b0;
		sd_cmd   <= CMD_NOP;
		sd_doe   <= 1'b0;
	end
	else if (!started) begin
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
			15'd20040: started <= 1'b1;
			default: ;
		endcase
	end
	else begin
		sd_cmd  <= f_cmd;
		sd_addr <= f_addr;
		sd_ba   <= f_ba;
		sd_dqm  <= f_dqm;
		sd_dout <= f_dout;
		sd_doe  <= f_doe;
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
