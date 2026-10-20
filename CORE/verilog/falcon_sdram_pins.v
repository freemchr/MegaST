//
// falcon_sdram_pins.v
//
// falcon_sdram.v with SDRAM pins (sdram_pinstage.v: what sdram_m65.v does for
// it in the core), for the simulations.
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
	output     [12:0] sd_addr,
	output      [1:0] sd_dqm,
	output      [1:0] sd_ba,
	output            sd_cs,
	output            sd_we,
	output            sd_ras,
	output            sd_cas,
	output            sd_clk
);

wire  [3:0] f_cmd;
wire [12:0] f_addr;
wire  [1:0] f_ba, f_dqm;
wire [15:0] f_dout, f_din;
wire        f_doe, ready;

// sd_doe: for the SDRAM model's bus conflict check
wire        sd_doe = stage.sd_doe;

falcon_sdram ctrl (
	.start_i(ready), .clk_32(clk_32), .clk_96(clk_96),
	.busy(busy), .burstcnt(burstcnt), .addr(addr), .dout(dout), .dout_ready(dout_ready),
	.rd(rd), .din(din), .be(be), .we(we),
	.sd_cmd_o(f_cmd), .sd_addr_o(f_addr), .sd_ba_o(f_ba), .sd_dqm_o(f_dqm),
	.sd_dout_o(f_dout), .sd_doe_o(f_doe), .sd_din_i(f_din)
);

sdram_pinstage stage (
	.init(init), .clk_96(clk_96), .ext_ready(ready),
	.ext_cmd(f_cmd), .ext_addr(f_addr), .ext_ba(f_ba), .ext_dqm(f_dqm),
	.ext_dout(f_dout), .ext_doe(f_doe), .ext_din(f_din),
	.sd_data(sd_data), .sd_addr(sd_addr), .sd_dqm(sd_dqm), .sd_ba(sd_ba),
	.sd_cs(sd_cs), .sd_we(sd_we), .sd_ras(sd_ras), .sd_cas(sd_cas), .sd_clk(sd_clk)
);

endmodule
