// Testbench top: Atari ST machine (atarist_m65) + SDRAM model
module tb_top (
  input         clk_96,
  input         clk_32,
  input         clk_2,
  input         init,
  input         reset_in,
  input   [2:0] cfg_mem,
  input         cfg_ste,
  input         dio_download,
  input  [23:1] dio_addr,
  input  [15:0] dio_data,
  input         dio_strobe,
  output        dio_strobe_ack,
  input         tos192k_in,
  input [119:0] kbd_matrix,
  input         cart_loaded,
  input         cfg_viking,
  // hard disk 0 (the testbench emulates the M2M firmware / vdrives)
  input   [1:0] hd_img_mounted,
  input  [31:0] img_size,
  output [31:0] hd_sd_lba,
  output  [1:0] hd_sd_rd,
  output  [1:0] hd_sd_wr,
  input   [1:0] hd_sd_ack,
  input   [7:0] sd_buff_addr,
  input  [15:0] sd_buff_dout,
  input         sd_buff_wr,
  output [15:0] hd_sd_buff_din,
  output  [7:0] video_r8, video_g8, video_b8,
  output        video_hs, video_vs, video_hblank, video_vblank, video_ce, video_mono,
  output [15:0] audio_l,
  output [23:1] dbg_cpu_a,
  output        dbg_cpu_as_n,
  output        dbg_cpu_rw,
  output [15:0] dbg_cpu_din,
  output        dbg_reset,
  output        dbg_sdram_errors,
  output [15:0] dbg_acsi_sel,
  output [15:0] dbg_acsi_busy,
  output  [3:0] dbg_acsi_state,
  output  [1:0] dbg_hd_present,
  output [15:0] dbg_acsi_irq,
  output  [7:0] dbg_acsi_din,
  output [15:0] dbg_dma_mode,
  output  [7:0] dbg_gpip
);
  reg [15:0] acsi_irq_cnt = 0; reg acsi_irq_d; reg [7:0] acsi_din;
  always @(posedge clk_32) begin
    acsi_irq_d <= dut.dma.acsi.irq;
    if (dut.dma.acsi.irq & ~acsi_irq_d) acsi_irq_cnt <= acsi_irq_cnt + 1'd1;
    if (dut.dma.acsi_reg_sel & ~acsi_sel_d) acsi_din <= dut.dma.cpu_din[7:0];
  end
  assign dbg_acsi_irq = acsi_irq_cnt;
  assign dbg_acsi_din = acsi_din;
  assign dbg_dma_mode = dut.dma.dma_mode;
  assign dbg_gpip     = dut.mfp_gpio_in;
  // debug counters for the ACSI path
  reg [15:0] acsi_sel_cnt = 0, acsi_busy_cnt = 0;
  reg acsi_sel_d, acsi_busy_d;
  always @(posedge clk_32) begin
    acsi_sel_d  <= dut.dma.acsi_reg_sel;
    acsi_busy_d <= dut.dma.acsi.busy;
    if (dut.dma.acsi_reg_sel & ~acsi_sel_d) acsi_sel_cnt <= acsi_sel_cnt + 1'd1;
    if (dut.dma.acsi.busy & ~acsi_busy_d) acsi_busy_cnt <= acsi_busy_cnt + 1'd1;
  end
  assign dbg_acsi_sel   = acsi_sel_cnt;
  assign dbg_acsi_busy  = acsi_busy_cnt;
  assign dbg_acsi_state = dut.acsi_ctrl.state;
  assign dbg_hd_present = dut.hd_present;
`ifdef ACSI_TRACE
  // ACSI trace: commands, IO controller data, DMA RAM accesses and status (build with VFLAGS=-DACSI_TRACE)
  always @(posedge clk_32) begin
    if (dut.dma.acsi.busy & ~acsi_busy_d) $display("ACSI busy: cmd %02x %02x %02x %02x %02x %02x", dut.dma.acsi.cmd_parameter[0], dut.dma.acsi.cmd_parameter[1], dut.dma.acsi.cmd_parameter[2], dut.dma.acsi.cmd_parameter[3], dut.dma.acsi.cmd_parameter[4], dut.dma.acsi.cmd_parameter[5]);
    if (dut.dma.io_data_in_strobe) $display("DIO in %04x wptr %0d rptr %0d", dut.dma.dio_data_in_reg, dut.dma.fifo_wptr, dut.dma.fifo_rptr);
    if (dut.dma.ram_access_strobe) $display("DMA ram %s %04x scnt %0d", dut.dma.dma_direction_out ? "rd" : "wr", dut.dma.dma_direction_out ? dut.dma.ram_din : dut.dma.ram_dout, dut.dma.dma_scnt);
    if (dut.dma.io_dma_ack) $display("DIO ack status %02x", dut.dma.dio_dma_status);
    if (dut.dma.acsi.clk_en && dut.dma.acsi.cpu_req && dut.dma.acsi.cpu_rw) $display("ACSI status read %02x", dut.dma.acsi.dma_status);
  end
`endif
  wire        sdram_clk, sdram_cke, sdram_ras_n, sdram_cas_n, sdram_we_n, sdram_cs_n, sdram_dqml, sdram_dqmh;
  wire  [1:0] sdram_ba;
  wire [12:0] sdram_a;
  wire [15:0] sdram_dq;

  atarist_m65 dut (
    .clk_32(clk_32), .clk_96(clk_96), .clk_2(clk_2), .init(init), .reset_in(reset_in),
    .cfg_mem(cfg_mem), .cfg_ste(cfg_ste), .cfg_mste(1'b0), .cfg_blitter(1'b0), .cfg_mono(1'b0),
    .cfg_psg_stereo(1'b0), .cfg_narrow_brd(1'b1), .cfg_mde60(1'b0), .cfg_fdc_wp(2'b00),
    .cfg_viking(cfg_viking), .cfg_ste_pads(1'b0), .cfg_cubase(1'b0), .cart_loaded(cart_loaded),
    .dio_download(dio_download), .dio_addr(dio_addr), .dio_data(dio_data), .dio_strobe(dio_strobe),
    .dio_strobe_ack(dio_strobe_ack), .tos192k_in(tos192k_in),
    .img_mounted(2'b00), .img_readonly(1'b0), .img_size(img_size), .sd_lba(), .sd_rd(), .sd_wr(),
    .sd_ack(1'b0), .sd_buff_addr(sd_buff_addr), .sd_buff_dout(sd_buff_dout), .sd_buff_din(), .sd_buff_wr(sd_buff_wr),
    .hd_img_mounted(hd_img_mounted), .hd_sd_lba(hd_sd_lba), .hd_sd_rd(hd_sd_rd), .hd_sd_wr(hd_sd_wr),
    .hd_sd_ack(hd_sd_ack), .hd_sd_buff_din(hd_sd_buff_din),
    .kbd_matrix(kbd_matrix), .joy_mouse(6'd0), .joy_stick(5'd0), .ste_pad0(21'd0), .ste_pad1(21'd0), .ps2_mouse(25'd0),
    .uart_rxd(1'b1), .uart_txd(), .uart_cts(1'b1), .uart_rts(), .uart_dtr(), .midi_rxd(1'b1), .midi_txd(),
    .par_din(8'hff), .par_dout(), .par_dout_en(), .par_strobe(), .par_busy(1'b1),
    .video_r(video_r8), .video_g(video_g8), .video_b(video_b8), .video_hs(video_hs), .video_vs(video_vs),
    .video_hblank(video_hblank), .video_vblank(video_vblank), .video_ce(video_ce), .video_31khz(video_mono),
    .audio_l(audio_l), .audio_r(),
    .floppy_led(), .hd_led(),
    .sdram_clk(sdram_clk), .sdram_cke(sdram_cke), .sdram_ras_n(sdram_ras_n), .sdram_cas_n(sdram_cas_n),
    .sdram_we_n(sdram_we_n), .sdram_cs_n(sdram_cs_n), .sdram_ba(sdram_ba), .sdram_a(sdram_a),
    .sdram_dqml(sdram_dqml), .sdram_dqmh(sdram_dqmh), .sdram_dq(sdram_dq)
  );

  sdram_model sdram (
    .clk(sdram_clk), .cke(sdram_cke), .cs_n(sdram_cs_n), .ras_n(sdram_ras_n), .cas_n(sdram_cas_n), .we_n(sdram_we_n),
    .ba(sdram_ba), .a(sdram_a), .dqml(sdram_dqml), .dqmh(sdram_dqmh), .dq(sdram_dq)
  );

  assign dbg_cpu_a    = dut.cpu_a;
  assign dbg_cpu_as_n = dut.cpu_as_n;
  assign dbg_cpu_rw   = dut.cpu_rw;
  assign dbg_cpu_din  = dut.cpu_din;
  assign dbg_reset    = dut.reset;
  assign dbg_sdram_errors = (sdram.errors != 0);
endmodule
