// Test bench of the Falcon machine as the MegaST core uses it (falcon_m65.sv):
// the SDRAM through a register stage like sdram_m65.v's (sdram_pinstage.v) on
// the strict SDRAM model; TOS, keyboard matrix and the 16-bit sector buffer
// interface of fdc_bridge.vhd are driven by sim_main.cpp.
module tb_top (
	input             clk_32,
	input             clk_96,
	input             init,
	input             reset,
	input             cold_reset,
	input             por,
	input       [3:0] ram_mb,
	input       [1:0] monitor,
	input             cpu_turbo,

	input      [23:1] dio_addr,
	input      [15:0] dio_data,
	input             dio_strobe,
	output            dio_strobe_ack,

	input     [119:0] kbd_matrix_n,
	input      [24:0] ps2_mouse,
	input      [31:0] joy0,

	input       [3:0] img_mounted,
	input      [31:0] img_size,
	output    [127:0] sd_lba,
	output      [3:0] sd_rd,
	output      [3:0] sd_wr,
	input       [3:0] sd_ack,
	input       [7:0] sd_buff_addr,
	input      [15:0] sd_buff_dout,
	output     [63:0] sd_buff_din,
	input             sd_buff_wr,

	output      [7:0] r,
	output      [7:0] g,
	output      [7:0] b,
	output            hblank,
	output            vblank,
	output            ce_pix,
	output     [15:0] audio_l,

	output            dbg_kbd_rd,       // the CPU reads the IKBD ACIA's data register
	output      [7:0] dbg_kbd_byte,
	output            dbg_sdram_err,
	output     [31:0] dbg_pc,           // CPU program counter
	output            dbg_cpu_rst       // the CPU's synchronized reset
);

wire  [3:0] e_cmd;
wire [12:0] e_addr;
wire  [1:0] e_ba, e_dqm;
wire [15:0] e_dout, e_din;
wire        e_doe, e_ready;

falcon_m65 #(.CLK_HZ(32083333)) dut (
	.clk_32(clk_32), .clk_96(clk_96), .reset(reset), .cold_reset(cold_reset), .por(por),
	.ram_mb(ram_mb), .monitor(monitor), .cpu_turbo(cpu_turbo),
	.dio_addr(dio_addr), .dio_data(dio_data), .dio_strobe(dio_strobe), .dio_strobe_ack(dio_strobe_ack),
	.kbd_matrix_n(kbd_matrix_n), .ps2_mouse(ps2_mouse), .joy0(joy0), .joy1(32'd0),
	.rtc({1'b0, 64'h0000_0042_6101_1200}),
	.img_mounted(img_mounted), .img_readonly(1'b0), .img_size(img_size),
	.sd_lba(sd_lba), .sd_rd(sd_rd), .sd_wr(sd_wr), .sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr), .sd_buff_dout(sd_buff_dout), .sd_buff_din(sd_buff_din), .sd_buff_wr(sd_buff_wr),
	.r(r), .g(g), .b(b), .hsync(), .vsync(), .hblank(hblank), .vblank(vblank), .ce_pix(ce_pix),
	.audio_l(audio_l), .audio_r(), .fdd_led(), .hdd_led(),
	.sdram_start(e_ready), .sd_cmd_o(e_cmd), .sd_addr_o(e_addr), .sd_ba_o(e_ba), .sd_dqm_o(e_dqm),
	.sd_dout_o(e_dout), .sd_doe_o(e_doe), .sd_din_i(e_din)
);

wire [15:0] sd_data;
wire [12:0] sd_addr;
wire  [1:0] sd_dqm, sd_ba;
wire        sd_cs, sd_we, sd_ras, sd_cas, sd_clk;

sdram_pinstage stage (
	.init(init), .clk_96(clk_96), .ext_ready(e_ready),
	.ext_cmd(e_cmd), .ext_addr(e_addr), .ext_ba(e_ba), .ext_dqm(e_dqm),
	.ext_dout(e_dout), .ext_doe(e_doe), .ext_din(e_din),
	.sd_data(sd_data), .sd_addr(sd_addr), .sd_dqm(sd_dqm), .sd_ba(sd_ba),
	.sd_cs(sd_cs), .sd_we(sd_we), .sd_ras(sd_ras), .sd_cas(sd_cas), .sd_clk(sd_clk)
);

sdram_strict sdram (
	.clk(sd_clk), .cs_n(sd_cs), .ras_n(sd_ras), .cas_n(sd_cas), .we_n(sd_we),
	.ba(sd_ba), .a(sd_addr), .dqml(sd_dqm[0]), .dqmh(sd_dqm[1]), .dq(sd_data),
	.fpga_drives(stage.sd_doe)
);

assign dbg_kbd_rd    = dut.system.acia.ik_rd_dr;
assign dbg_kbd_byte  = dut.system.acia.rdr_ikbd;
assign dbg_sdram_err = (sdram.errors != 0);
assign dbg_pc        = dut.system.dbg_pc;
assign dbg_cpu_rst   = dut.system.cpu.rst;

// guest memory for the C++ side (big endian bytes), through the SDRAM model
function [22:0] sd_idx(input [20:0] q, input [1:0] k);
	sd_idx = {q[9:8], q[20:10], q[7:0], k};
endfunction
export "DPI-C" function guest_peek8;
function byte unsigned guest_peek8(input int unsigned a);
	reg [15:0] w;
	w = sdram.mem[sd_idx(a[23:3], a[2:1])];
	// falcon_memarb byte-swaps the 64-bit words: DDR byte k (bits 8k+7..8k) = guest byte k,
	// and the SDRAM beat j holds DDR bytes 2j (low) and 2j+1 (high)
	guest_peek8 = a[0] ? w[15:8] : w[7:0];
endfunction

final $display("SDRAM: %0d refreshes, %0d timing errors", sdram.refs, sdram.errors);

endmodule
