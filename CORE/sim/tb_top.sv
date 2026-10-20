// Testbench top: Atari ST machine (atarist_m65) + SDRAM model
module tb_top (
  input         clk_96,
  input         clk_32,
  input         clk_2,
  input         init,
  input         reset_in,
  input   [2:0] cfg_mem,
  input         cfg_ste,
  input         cfg_mste,      // 1 = Mega STe; with cfg_ste: STEroids
  input         dio_download,
  input  [23:1] dio_addr,
  input  [15:0] dio_data,
  input         dio_strobe,
  output        dio_strobe_ack,
  input         tos192k_in,
  input [119:0] kbd_matrix,
  input   [5:0] joy_mouse,
  input         cart_loaded,
  input         cfg_viking,
  input         cfg_crop,
  input         cfg_mono,      // 1 = SM124 monochrome monitor
  input         cfg_mde60,     // 1 = mono 60 Hz mode
  input         cfg_full_brd,  // 1 = full borders (menu "Full borders")
  input         cfg_real_floppy, // 1 = drive A is the internal floppy drive (RFLOPPY=, drive model in tb.cpp)
  input         cfg_fdc_retry,   // 1 = the controller repeats failed sector reads (RFLOPPY_RAW=1: off)
  output        rfd_sel_a, rfd_motor, rfd_side, rfd_dir_in, rfd_step, rfd_wgate,
  input         rfd_rdata, rfd_index, rfd_track0, rfd_wprot,
  // hard disk 0 (the testbench emulates the M2M firmware / vdrives)
  input   [1:0] fd_img_mounted,
  output [31:0] fd_sd_lba,
  output  [1:0] fd_sd_rd,
  output  [1:0] fd_sd_wr,
  input         fd_sd_ack,
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
`ifdef KBD_TRACE
  // trace the bytes that the IKBD sends to the keyboard ACIA
  reg kbd_rx_d;
  always @(posedge clk_32) begin
    kbd_rx_d <= dut.kbd_acia.serial_rx_data_available;
    if (dut.kbd_acia.serial_rx_data_available & ~kbd_rx_d) $display("IKBD byte %h", dut.kbd_acia.serial_rx_data);
  end
`endif
`ifdef FDC_TRACE
  // trace the FDC of either floppy path (image: fdc1772.sv, real drive: wd1772_m65.v), build with VFLAGS=-DFDC_TRACE:
  // CPU register writes with the PSG drive select/side, status reads when the value changes, and at each INTRQ
  // the number and the checksum of the bytes moved by DMA since the last command (compare the two paths' logs)
  reg fdc_sel_d, fdc_dsel_d, fdc_irq_d; reg [7:0] fdc_last_st = 8'hff;
  integer fdc_n = 0, dma_n = 0, dma_sum = 0;
  always @(posedge clk_32) begin
    fdc_sel_d  <= dut.fdc_sel;
    fdc_dsel_d <= dut.dma.fdc_dma_sel;
    fdc_irq_d  <= dut.fdc_irq;
    if (dut.dma.fdc_dma_sel & ~fdc_dsel_d & dut.fdc_rw) begin
      dma_n   <= dma_n + 1;
      dma_sum <= (dma_sum * 31 + dut.fdc_dout) & 32'h7fffffff;
    end
    if (dut.fdc_sel & ~fdc_sel_d & ~dut.dma.fdc_dma_sel & fdc_n < 20000) begin
      if (!dut.fdc_rw) begin
        fdc_n <= fdc_n + 1;
        $display("FDC write reg %0d = %02x  (sel %b side %b)", dut.fdc_addr, dut.fdc_din, dut.floppy_sel, dut.floppy_side);
        if (dut.fdc_addr == 0) begin dma_n <= 0; dma_sum <= 0; end
      end else if (dut.fdc_addr != 0 || dut.fdc_dout != fdc_last_st) begin
        fdc_n <= fdc_n + 1;
        $display("FDC read  reg %0d = %02x", dut.fdc_addr, dut.fdc_dout);
        if (dut.fdc_addr == 0) fdc_last_st <= dut.fdc_dout;
      end
    end
    if (dut.fdc_irq & ~fdc_irq_d) $display("FDC INTRQ  dma bytes %0d sum %08x", dma_n, dma_sum);
  end
  // the buffered read with retries of wd1772_m65.v: each attempt's status and the end of the command
  always @(posedge clk_32) begin
    if (dut.wd1772_m65.start_read) $display("FDC RETRY start cmd %02x", dut.wd1772_m65.cpu_din);
    if (dut.wd1772_m65.acc_end && dut.wd1772_m65.acc_kind == 2'd1 && dut.wd1772_m65.mode == 2'd1)
      $display("FDC RETRY attempt status %02x, %0d bytes, %0d retries left", dut.wd1772_m65.ip_dout,
        dut.wd1772_m65.cap_n, dut.wd1772_m65.tries_left);
    if (dut.wd1772_m65.cmd_wr && !dut.wd1772_m65.sel_d && dut.wd1772_m65.mode != 2'd0)
      $display("FDC RETRY %s command %02x in mode %0d", dut.wd1772_m65.cpu_din[7:4] == 4'hd ? "ended by" : "ignored",
        dut.wd1772_m65.cpu_din, dut.wd1772_m65.mode);
  end
  // the command log of the real floppy controller (JTAG probe, tools/probe4.tcl LOG=1): show each entry
  // when the next command has ended, so that its status is filled in
  reg [15:0] fdc_log_count_d = 0;
  always @(posedge clk_32) begin
    fdc_log_count_d <= fdc_log_count;
    if (fdc_log_count != fdc_log_count_d && fdc_log_count >= 2)
      $display("FDC LOG #%0d cmd %02x track %0d data %0d sector %0d side %0d dma %0d status %02x buffered %0d retries %0d", fdc_log_count - 2,
        fdc_log_entry[7:0], fdc_log_entry[15:8], fdc_log_entry[23:16], fdc_log_entry[31:24], fdc_log_entry[50],
        fdc_log_entry[49:40], fdc_log_entry[39:32], fdc_log_entry[51], fdc_log_entry[55:52]);
  end
`endif
`ifdef RTC_TRACE
  // trace the accesses to the Mega ST real time clock
  reg rtc_sel_d; integer rtc_n = 0;
  always @(posedge clk_32) begin
    rtc_sel_d <= dut.rtc_sel;
    if (dut.rtc_sel & ~rtc_sel_d & rtc_n < 200) begin
      rtc_n <= rtc_n + 1;
      if (dut.rw) $display("RTC read  reg %h (bank %0d) = %h", dut.mbus_a[4:1], dut.rp5c15.mode[0], dut.rtc_data_out);
      else        $display("RTC write reg %h = %h", dut.mbus_a[4:1], dut.mbus_dout[3:0]);
    end
  end
`endif
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
  reg [3:0] acsi_state_d;
  always @(posedge clk_32) acsi_state_d <= dut.acsi_ctrl.state;
  // ACSI trace: commands, IO controller data, DMA RAM accesses and status (build with VFLAGS=-DACSI_TRACE)
  always @(posedge clk_32) begin
    if (dut.dma.acsi.busy & ~acsi_busy_d) $display("ACSI busy: cmd %02x %02x %02x %02x %02x %02x", dut.dma.acsi.cmd_parameter[0], dut.dma.acsi.cmd_parameter[1], dut.dma.acsi.cmd_parameter[2], dut.dma.acsi.cmd_parameter[3], dut.dma.acsi.cmd_parameter[4], dut.dma.acsi.cmd_parameter[5]);
    if (dut.dma.io_data_in_strobe) $display("DIO in %04x wptr %0d rptr %0d", dut.dma.dio_data_in_reg, dut.dma.fifo_wptr, dut.dma.fifo_rptr);
    if (dut.dma.ram_access_strobe) $display("DMA ram %s %04x scnt %0d", dut.dma.dma_direction_out ? "rd" : "wr", dut.dma.dma_direction_out ? dut.dma.ram_din : dut.dma.ram_dout, dut.dma.dma_scnt);
    if (dut.dma.io_data_out_strobe) $display("DIO out %04x wptr %0d rptr %0d", dut.dma.dio_data_out_reg, dut.dma.fifo_wptr, dut.dma.fifo_rptr);
    if (dut.dma.fifo_reset) $display("DMA fifo reset (direction %0d)", dut.dma.cpu_din[8]);
    if (dut.dma.clk_en && dut.dma.cpu_req && !dut.dma.cpu_rw) $display("DMA %s write %04x", dut.dma.cpu_a1 ? "mode" : "data", dut.dma.cpu_din);
    if (dut.acsi_ctrl.state != acsi_state_d) $display("ACSI ctrl state %0d -> %0d (abort %0d)", acsi_state_d, dut.acsi_ctrl.state, dut.acsi_ctrl.abort);
    if (dut.dma.io_dma_ack) $display("DIO ack status %02x", dut.dma.dio_dma_status);
    if (dut.dma.acsi.clk_en && dut.dma.acsi.cpu_req && dut.dma.acsi.cpu_rw) $display("ACSI status read %02x", dut.dma.acsi.dma_status);
  end
`endif
  wire        sdram_clk, sdram_cke, sdram_ras_n, sdram_cas_n, sdram_we_n, sdram_cs_n, sdram_dqml, sdram_dqmh;
  wire  [1:0] sdram_ba;
  wire [12:0] sdram_a;
  wire [15:0] sdram_dq;
  wire [55:0] fdc_log_entry;
  wire [15:0] fdc_log_count;
  wire  [7:0] fdc_log_idx = fdc_log_count[7:0] - 8'd2;

`ifdef BRAM_MEM
  // MEGA65 R3 variant: ST RAM, TOS and cartridge in block RAM (VFLAGS=-DBRAM_MEM ./build.sh)
  atarist_m65 #(.BRAM_MEM(1)) dut (
`else
  atarist_m65 dut (
`endif
    .clk_32(clk_32), .clk_96(clk_96), .clk_2(clk_2), .init(init), .reset_in(reset_in),
    .cfg_mem(cfg_mem), .cfg_ste(cfg_ste), .cfg_mste(cfg_mste), .cfg_blitter(1'b0), .cfg_mono(cfg_mono),
    .cfg_psg_stereo(1'b0), .cfg_narrow_brd(~cfg_full_brd), .cfg_mde60(cfg_mde60), .cfg_fdc_wp(2'b00),
    .cfg_viking(cfg_viking), .cfg_ste_pads(1'b0), .cfg_cubase(1'b0), .cfg_crop(cfg_crop),
    .rtc({1'b0, 8'h40, 8'h01, 8'h26, 8'h09, 8'h28, 8'h14, 8'h35, 8'h07}),  // Mon 2026-09-28 14:35:07 .cart_loaded(cart_loaded),
    .dio_download(dio_download), .dio_addr(dio_addr), .dio_data(dio_data), .dio_strobe(dio_strobe),
    .dio_strobe_ack(dio_strobe_ack), .tos192k_in(tos192k_in),
    .img_mounted(fd_img_mounted), .img_readonly(1'b0), .img_size(img_size), .sd_lba(fd_sd_lba), .sd_rd(fd_sd_rd), .sd_wr(fd_sd_wr),
    .sd_ack(fd_sd_ack), .sd_buff_addr(sd_buff_addr), .sd_buff_dout(sd_buff_dout), .sd_buff_din(), .sd_buff_wr(sd_buff_wr),
    .hd_img_mounted(hd_img_mounted), .hd_sd_lba(hd_sd_lba), .hd_sd_rd(hd_sd_rd), .hd_sd_wr(hd_sd_wr),
    .hd_sd_ack(hd_sd_ack), .hd_sd_buff_din(hd_sd_buff_din),
    .kbd_matrix(kbd_matrix), .joy_mouse(joy_mouse), .joy_stick(5'd0), .ste_pad0(21'd0), .ste_pad1(21'd0), .ps2_mouse(25'd0),
    .uart_rxd(1'b1), .uart_txd(), .uart_cts(1'b1), .uart_rts(), .uart_dtr(), .midi_rxd(1'b1), .midi_txd(),
    .par_din(8'hff), .par_dout(), .par_dout_en(), .par_strobe(), .par_busy(1'b1),
    .video_r(video_r8), .video_g(video_g8), .video_b(video_b8), .video_hs(video_hs), .video_vs(video_vs),
    .video_hblank(video_hblank), .video_vblank(video_vblank), .video_ce(video_ce), .video_31khz(video_mono),
    .audio_l(audio_l), .audio_r(),
    .floppy_led(), .hd_led(),
    .cfg_real_floppy(cfg_real_floppy), .cfg_fdc_retry(cfg_fdc_retry), .rfd_sel_a(rfd_sel_a), .rfd_motor(rfd_motor), .rfd_side(rfd_side),
    .rfd_dir_in(rfd_dir_in), .rfd_step(rfd_step), .rfd_wgate(rfd_wgate), .rfd_wdata(),
    .rfd_rdata(rfd_rdata), .rfd_index(rfd_index), .rfd_track0(rfd_track0), .rfd_wprot(rfd_wprot),
    .sdram_clk(sdram_clk), .sdram_cke(sdram_cke), .sdram_ras_n(sdram_ras_n), .sdram_cas_n(sdram_cas_n),
    .sdram_we_n(sdram_we_n), .sdram_cs_n(sdram_cs_n), .sdram_ba(sdram_ba), .sdram_a(sdram_a),
    .sdram_dqml(sdram_dqml), .sdram_dqmh(sdram_dqmh), .sdram_dq(sdram_dq),
    .dbg_fdc_idx(fdc_log_idx), .dbg_fdc_entry(fdc_log_entry), .dbg_fdc_count(fdc_log_count)
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
