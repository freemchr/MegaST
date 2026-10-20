//============================================================================
//  MEGA65 replacement for Falcon_MiSTer's tb/system/ddr3_model.sv: the
//  MiSTer DDRAM port goes through the SDRAM adapter of the MEGA65 core
//  (CORE/verilog/falcon_sdram.v) into a strict SDRAM model
//  (CORE/sim/falcon_sdram/sdram_strict.v), which checks the SDRAM timing.
//
//  Same ports and the same DPI functions as the original (ddr_peek/ddr_poke:
//  64-bit word index in the 16 MB window), so sim_main.cpp works unchanged.
//  +rom= / +cart= are loaded into the SDRAM at the first clock.
//
//  MEGA65 port done by Chris Freeman in 2026, licensed under GPL v3
//============================================================================

module ddr3_m65
(
	input             clk,
	input             clk_96,
	output            DDRAM_BUSY,
	input       [7:0] DDRAM_BURSTCNT,
	input      [28:0] DDRAM_ADDR,
	output     [63:0] DDRAM_DOUT,
	output            DDRAM_DOUT_READY,
	input             DDRAM_RD,
	input      [63:0] DDRAM_DIN,
	input       [7:0] DDRAM_BE,
	input             DDRAM_WE
);

wire [15:0] sd_data;
wire [12:0] sd_addr;
wire  [1:0] sd_dqm, sd_ba;
wire        sd_cs, sd_we, sd_ras, sd_cas, sd_clk;

// the FPGA configuration is done at once; the adapter initializes the SDRAM (~210 us)
reg  [3:0] init_cnt = 4'd0;
always @(posedge clk) if (init_cnt != 4'd15) init_cnt <= init_cnt + 4'd1;

falcon_sdram adapter
(
	.init(init_cnt != 4'd15), .clk_32(clk), .clk_96(clk_96),
	.busy(DDRAM_BUSY), .burstcnt(DDRAM_BURSTCNT[2:0]), .addr(DDRAM_ADDR[20:0]),
	.dout(DDRAM_DOUT), .dout_ready(DDRAM_DOUT_READY),
	.rd(DDRAM_RD), .din(DDRAM_DIN), .be(DDRAM_BE), .we(DDRAM_WE),
	.sd_data(sd_data), .sd_addr(sd_addr), .sd_dqm(sd_dqm), .sd_ba(sd_ba),
	.sd_cs(sd_cs), .sd_we(sd_we), .sd_ras(sd_ras), .sd_cas(sd_cas), .sd_clk(sd_clk)
);

sdram_strict sdram
(
	.clk(sd_clk), .cs_n(sd_cs), .ras_n(sd_ras), .cas_n(sd_cas), .we_n(sd_we),
	.ba(sd_ba), .a(sd_addr), .dqml(sd_dqm[0]), .dqmh(sd_dqm[1]), .dq(sd_data),
	.fpga_drives(adapter.sd_doe[0])
);

// 16-bit SDRAM word k (0..3) of the 64-bit word q, as falcon_sdram.v maps it
function [22:0] sd_idx(input [20:0] q, input [1:0] k);
	sd_idx = {q[9:8], q[20:10], q[7:0], k};
endfunction

export "DPI-C" function ddr_peek;
export "DPI-C" function ddr_poke;
function longint unsigned ddr_peek(input int unsigned qaddr);
	ddr_peek = {sdram.mem[sd_idx(qaddr[20:0], 2'd3)], sdram.mem[sd_idx(qaddr[20:0], 2'd2)],
	            sdram.mem[sd_idx(qaddr[20:0], 2'd1)], sdram.mem[sd_idx(qaddr[20:0], 2'd0)]};
endfunction
function void ddr_poke(input int unsigned qaddr, input longint unsigned data, input byte unsigned be);
	integer i;
	for (i = 0; i < 8; i = i + 1)
		if (be[i]) sdram.mem[sd_idx(qaddr[20:0], i[2:1])][8 * i[0] +: 8] = data[8 * i +: 8];
endfunction

// ROM / cartridge images (hex, 64-bit words) into the SDRAM
reg [63:0] img [0:(1<<21)-1];
reg        loaded = 1'b0;
reg        have_rom = 1'b0, have_cart = 1'b0;
initial begin
	string f;
	if ($value$plusargs("rom=%s", f))  begin $readmemh(f, img, 'hE00000 >> 3); have_rom = 1'b1; end
	if ($value$plusargs("cart=%s", f)) begin $readmemh(f, img, 'hFA0000 >> 3); have_cart = 1'b1; end
end
always @(posedge clk) if (!loaded) begin
	integer q;
	loaded <= 1'b1;
	if (have_rom)  for (q = 'hE00000 >> 3; q < 'hF00000 >> 3; q = q + 1) ddr_poke(q, img[q], 8'hFF);
	if (have_cart) for (q = 'hFA0000 >> 3; q < 'hFC0000 >> 3; q = q + 1) ddr_poke(q, img[q], 8'hFF);
end

final $display("SDRAM: %0d refreshes, %0d timing errors", sdram.refs, sdram.errors);

endmodule
