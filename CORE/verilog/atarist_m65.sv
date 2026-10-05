//============================================================================
//  Atari ST/STe for MEGA65
//
//  This is the Atari ST machine of AtariST_MiSTer (AtariST.sv) with all
//  MiSTer framework (HPS) dependencies removed, so that it can be wrapped
//  by the MiSTer2MEGA65 framework (see CORE/vhdl/main.vhd).
//
//  Changes compared to AtariST.sv:
//    - no hps_io/hps_ext: configuration, TOS/cartridge loading, floppy and
//      hard disk access and keyboard/joystick/mouse input are provided via
//      plain ports
//    - the ACSI commands are executed in hardware (acsi_ctrl.sv) instead of
//      by the MiSTer's ARM
//    - serial port, MIDI and the parallel port are plain pins (MEGA65: PMOD)
//    - no MT32-pi, no Cubase dongles
//    - no line doubler: the M2M framework does the scandoubling (VGA) and
//      the scaling (HDMI); the Viking card's 1280x1024 is downscaled to
//      640x512 (viking_scale.sv)
//    - the TOS image is always stored at $E00000 in SDRAM, the 192k TOS
//      detection is done by the loader
//    - SDRAM controller for the MEGA65 R4/R5/R6 board (sdram_m65.v)
//
//  Atari ST
//  Copyright (C) Till Harbaum <till@harbaum.org>
//  Copyright (C) Gyorgy Szombathelyi <gyurco@freemail.hu>
//
//  Port to MiSTer
//  Copyright (C) Alexey Melnikov
//
//  Port to MEGA65 (MiSTer2MEGA65) 2026
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//============================================================================

module atarist_m65
#(
	// 0: ST RAM and TOS in the SDRAM (MEGA65 R4/R5/R6, sdram_m65.v)
	// 1: in the FPGA's block RAM (MEGA65 R3/R3A, bram_m65.v): 512 KB ST RAM, no Viking card
	parameter BRAM_MEM = 0
)
(
	input         clk_32,          // 32.08 MHz system clock
	input         clk_96,          // 96.25 MHz SDRAM clock (phase aligned to clk_32)
	input         clk_2,           // 2.005 MHz IKBD clock  (phase aligned to clk_32)
	input         init,            // high while the clocks are not stable (power-on reset)
	input         reset_in,        // soft reset (clk_32 domain)

	// configuration (clk_32 domain)
	input   [2:0] cfg_mem,         // 0=512K, 1=1M, 2=2M, 3=4M, 4=8M, 5=14M
	input         cfg_ste,         // STe chipset
	input         cfg_mste,        // Mega STe (16 MHz CPU); together with cfg_ste: "STEroids"
	input         cfg_blitter,     // Blitter in ST mode (always on in STe mode)
	input         cfg_mono,        // SM124 monochrome monitor
	input         cfg_psg_stereo,
	input         cfg_narrow_brd,  // MiSTer's TOS_CONTROL_BORDER (default on)
	input         cfg_mde60,       // mono 60 Hz mode (0 = 71 Hz)
	input   [1:0] cfg_fdc_wp,      // write protect floppy B/A (menu setting or read-only image)
	input         cfg_viking,      // Viking/SM194 1280x1024 card
	input         cfg_ste_pads,    // STe enhanced joystick ports instead of the ST joystick ports
	input         cfg_cubase,      // Cubase 2/3 dongle in the cartridge port
	input         cfg_crop,        // blank the border: only the graphics area is active (HDMI zoom-in)

	// MEGA65 real time clock (M2M format, see rp5c15_m65.sv)
	input  [64:0] rtc,

	// TOS loader (clk_32 domain)
	// dio_download must be high while the TOS image is being written. Each
	// word is written when dio_strobe toggles, dio_strobe_ack follows
	// dio_strobe as soon as the word has been written to SDRAM.
	input         dio_download,
	input  [23:1] dio_addr,
	input  [15:0] dio_data,
	input         dio_strobe,
	output        dio_strobe_ack,
	input         tos192k_in,
	input         cart_loaded,     // a cartridge image has been loaded to $FA0000

	// Floppy drives: MiSTer "SD" interface (clk_32 domain)
	input   [1:0] img_mounted,
	input         img_readonly,
	input  [31:0] img_size,
	output [31:0] sd_lba,
	output  [1:0] sd_rd,
	output  [1:0] sd_wr,
	input         sd_ack,
	input   [7:0] sd_buff_addr,
	input  [15:0] sd_buff_dout,
	output [15:0] sd_buff_din,
	input         sd_buff_wr,

	// Hard disks (ACSI target 0/1): MiSTer "SD" interface (clk_32 domain),
	// the sector buffer interface (sd_buff_*) is shared with the floppy drives
	input   [1:0] hd_img_mounted,
	output [31:0] hd_sd_lba,
	output  [1:0] hd_sd_rd,
	output  [1:0] hd_sd_wr,
	input   [1:0] hd_sd_ack,
	output [15:0] hd_sd_buff_din,

	// keyboard, mouse and joysticks
	input [119:0] kbd_matrix,      // low active ST keyboard matrix (column*8+row)
	input   [5:0] joy_mouse,       // ST port 0 (mouse port): {btn2, fire, right, left, down, up}, high active
	input   [4:0] joy_stick,       // ST port 1 (joystick):   {fire, right, left, down, up}, high active
	input  [20:0] ste_pad0,        // STe joypad A (MiSTer format, see ste_joypad.v), high active
	input  [20:0] ste_pad1,        // STe joypad B
	input  [24:0] ps2_mouse,       // MiSTer PS/2 mouse format (1351 mouse emulation)

	// serial port (MFP), high active levels like on the TTL side of a MAX232
	input         uart_rxd,
	output        uart_txd,
	input         uart_cts,
	output        uart_rts,
	output        uart_dtr,

	// MIDI (ACIA)
	input         midi_rxd,
	output        midi_txd,

	// parallel port
	input   [7:0] par_din,
	output  [7:0] par_dout,
	output        par_dout_en,     // 1 = the ST drives the data lines
	output        par_strobe,
	input         par_busy,

	// video output (clk_32 domain)
	output  [7:0] video_r,
	output  [7:0] video_g,
	output  [7:0] video_b,
	output        video_hs,
	output        video_vs,
	output        video_hblank,
	output        video_vblank,
	output        video_ce,        // pixel clock enable: 16 MHz (color) or 32 MHz (mono, Viking)
	output        video_31khz,     // 1 = 31 kHz mode (71 Hz mono, Viking): no scandoubler needed

	// audio output (clk_32 domain)
	output [15:0] audio_l,
	output [15:0] audio_r,

	output        floppy_led,
	output        hd_led,

	// SDRAM
	output        sdram_clk,
	output        sdram_cke,
	output        sdram_ras_n,
	output        sdram_cas_n,
	output        sdram_we_n,
	output        sdram_cs_n,
	output  [1:0] sdram_ba,
	output [12:0] sdram_a,
	output        sdram_dqml,
	output        sdram_dqmh,
	inout  [15:0] sdram_dq,

	// debugging (JTAG probe in mega65.vhd): the last 4 bytes the CPU read from the keyboard ACIA's
	// data register, the newest one in bits 7..0
	output reg [31:0] dbg_kbd_bytes
);

wire UART_RXD = uart_rxd;
wire UART_CTS = uart_cts;

assign floppy_led = ~&floppy_sel;

/////////////////////////////  A/V output  ///////////////////////////////////////

wire [11:0] hstart[8] = '{ 145, 161, 148, 0,  193, 257, 148, 0};
wire [11:0] hend[8]   = '{1841,1841, 788, 0, 1793,1745, 788, 0};
wire [11:0] vstart[8] = '{  19,  28,  37, 0,   28,  46, 122, 0};
wire [11:0] vend[8]   = '{ 261, 311, 437, 0,  252, 293, 522, 0};

reg       hblank_gen, vblank_gen;
reg [2:0] mode;
reg       vsync_n_l, hsync_n_l;
wire      pix_active;   // MEGA65: the shifter outputs graphics (not the border), see gstshifter.v
// MEGA65: cropping: the lines with graphics (DE) in the previous frame
reg [11:0] crop_vfirst, crop_vlast, crop_vfirst_n, crop_vlast_n;
reg        crop_line_de, crop_frame_de;
reg        crop_vbl;
always @(posedge clk_32) begin
	reg  [11:0] hcnt,vcnt;

	hcnt <= hcnt + 1'd1;
	hsync_n_l <= hsync_n;

	if (de) crop_line_de <= 1'b1;

	if(~hsync_n_l & hsync_n) begin
		hcnt <= 0;
		vcnt <= vcnt + 1'd1;
		if (crop_line_de) begin
			if (!crop_frame_de) crop_vfirst_n <= vcnt;
			crop_vlast_n  <= vcnt;
			crop_frame_de <= 1'b1;
		end
		crop_line_de <= 1'b0;
		crop_vbl <= (vcnt + 1'd1 < crop_vfirst) || (vcnt + 1'd1 > crop_vlast);
	end

	if (hsync_n_l & ~hsync_n) begin
		vsync_n_l <= vsync_n;
	end

	if(vsync_n_l & ~vsync_n) begin
		mode <= {mono ? mde60 : narrow_brd, mono, ~mono & pal};
		vcnt <= 0;
		crop_vfirst   <= crop_vfirst_n;
		crop_vlast    <= crop_vlast_n;
		crop_frame_de <= 1'b0;
		crop_vbl      <= 1'b1;
	end

	if(hcnt == hstart[mode]) begin
		hblank_gen <= 0;
		if(vcnt == vstart[mode]) vblank_gen <= 0;
		if(vcnt == vend[mode])   vblank_gen <= 1;
	end

	if(hcnt == hend[mode]) hblank_gen <= 1;
end

// MEGA65: register the video signals and create a constant pixel clock enable:
// 16 MHz in the color modes (low res pixels are doubled horizontally, med res
// is native) and 32 MHz in the 71 Hz monochrome mode and in the Viking mode.
reg [7:0] vid_r, vid_g, vid_b;
reg       vid_hs, vid_vs, vid_hbl, vid_vbl;
reg       vid_ce16;
reg       vid_viking;
always @(posedge clk_32) begin
	vid_ce16 <= ~vid_ce16;
	// switch at the end of a frame
	if (viking_active ? viking_s_vs : ~vsync_n_l) vid_viking <= viking_active;
	if (vid_viking) begin
		vid_r    <= viking_grey;
		vid_g    <= viking_grey;
		vid_b    <= viking_grey;
		vid_hs   <= viking_s_hs;
		vid_vs   <= viking_s_vs;
		vid_hbl  <= viking_s_hbl;
		vid_vbl  <= viking_s_vbl;
	end else begin
		vid_r    <= {r, r};
		vid_g    <= {g, g};
		vid_b    <= {b, b};
		vid_hs   <= ~hsync_n_l;
		vid_vs   <= ~vsync_n_l;
		vid_hbl  <= hblank_gen | (cfg_crop & ~pix_active);
		vid_vbl  <= vblank_gen | (cfg_crop & crop_vbl);
	end
end

assign video_r      = vid_r;
assign video_g      = vid_g;
assign video_b      = vid_b;
assign video_hs     = vid_hs;
assign video_vs     = vid_vs;
assign video_hblank = vid_hbl;
assign video_vblank = vid_vbl;
assign video_31khz  = mode[1] | vid_viking;
assign video_ce     = (mode[1] | vid_viking) ? 1'b1 : vid_ce16;

/* ------------------------------------------------------------------------------ */

wire [15:0] audio_mix_l;
wire [15:0] audio_mix_r;
assign audio_l = {1'b0, audio_mix_l[15:1]};
assign audio_r = {1'b0, audio_mix_r[15:1]};

//////////////////////////////////////////////////////////////////////////////////
////////////////////////// Atari ST core /////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////

// enable additional ste/megaste features
// MEGA65 R3 (block RAM): always 512 KB
wire [2:0] mem_size      = BRAM_MEM ? 3'd0 : cfg_mem;
wire       MEM512K       = (mem_size == 3'd0);
wire       MEM1M         = (mem_size == 3'd1);
wire       MEM2M         = (mem_size == 3'd2);
wire       MEM4M         = (mem_size == 3'd3);
wire       MEM8M         = (mem_size == 3'd4);
wire       MEM14M        = (mem_size == 3'd5);
wire [1:0] fdc_wp        = cfg_fdc_wp;
// MiSTer's status bit 8 is TOS_CONTROL_VIDEO_COLOR (1 = color monitor), despite the wire's name
wire       mono_monitor  = ~cfg_mono;
wire [7:0] acsi_enable   = {6'd0, hd_present};
wire       blitter_en    = (cfg_blitter || ste);
wire       psg_stereo    = cfg_psg_stereo;
wire       ste           = cfg_ste || cfg_mste;
wire       mste          = cfg_mste;
wire       steroids      = cfg_ste && cfg_mste && !BRAM_MEM;  // a STE on steroids (needs the SDRAM)
wire       cubase_enable = cfg_cubase;
wire       viking_en     = cfg_viking && !BRAM_MEM;    // the Viking card needs the SDRAM
wire       narrow_brd    = cfg_narrow_brd;
wire       mde60         = cfg_mde60;

// synchronized reset signal
reg       reset;
reg [7:0] reset_cnt = 8'd0;
always @(posedge clk_32) begin
	reg m8_en;

	m8_en <= mhz8_en1;
	if(m8_en) reset <= 0;

	if(~&reset_cnt) begin
		reset <= 1;
		reset_cnt <= reset_cnt + 1'd1;
	end
	if(reset_in | init) reset_cnt <= 0;
end

reg peripheral_reset;
always @(posedge clk_32) peripheral_reset <= reset | ~cpu_reset_n_o;

reg ikbd_reset;
always @(posedge clk_2) ikbd_reset <= reset | ~cpu_reset_n_o;

// MCU signals
wire        mhz4, mhz4_en, clk16;
wire        clk16_en = ~clk16;
wire        mcu_dtack_n;
wire        hsync_n, vsync_n;
wire        rom0_n, rom1_n, rom2_n, rom3_n, rom4_n, rom5_n, rom6_n, romp_n;
wire        ras0_n, ras1_n;
wire        mfpint_n, mfpcs_n, mfpiack_n;
wire        sndir, sndcs;
wire        n6850, fcs_n;
wire        rtccs_n, rtcrd_n, rtcwr_n;
wire        rtc_sel;          // MEGA65: Mega ST real time clock, see below
wire  [3:0] rtc_data_out;
wire        sint;
wire [15:0] mcu_dout;
wire        ras_n = ras0_n & ras1_n;
wire        button_n, joywe_n, joyrl_n, joywl, joyrh_n;

// dma
wire        rdy_o, rdy_i, mcu_bg_n, mcu_br_n, mcu_bgack_n;

// compatibility for viking
wire  [1:0] bus_cycle;

// for other peripherals
wire        iodevice = ~as_n & fc2 & (fc0 ^ fc1) & mbus_a[23:16] == 8'hff;

// CPU signals
wire        mhz8, mhz8_en1, mhz8_en2;
wire        berr_n;
wire        ipl0_n, ipl1_n, ipl2_n;
wire        cpu_fc0, cpu_fc1, cpu_fc2;
wire        cpu_as_n, cpu_rw, cpu_uds_n, cpu_lds_n, vma_n, vpa_n, cpu_E;
wire        cpu_reset_n_o;
wire [15:0] cpu_din, cpu_dout;
wire [23:1] cpu_a;

wire        rom_n = rom0_n & rom1_n & rom2_n & rom3_n & rom4_n & rom5_n & rom6_n & romp_n;

// MEGA65: without a cartridge the cartridge area reads as $FFFF
wire [15:0] rom_data = ((!rom3_n | !rom4_n) & ~cart_loaded) ? 16'hFFFF : rom_data_out;

assign      cpu_din =
              ~fcs_n ? dma_data_out :
              blitter_sel ? blitter_data_out :
              !rdat_n  ? shifter_dout :
              !(mfpcs_n & mfpiack_n)? { 8'hff, mfp_data_out } :
              (!rom3_n & cubase_enable) ? {cubase_dout, 8'hff} :
              !rom_n   ? rom_data :
              n6850    ? { mbus_a[2] ? midi_acia_data_out : kbd_acia_data_out, 8'hFF } :
              sndcs    ? { snd_data_out, 8'hFF }:
              mste_ctrl_sel ? {8'hff, mste_ctrl_data_out }:
              rtc_sel  ? { 12'hfff, rtc_data_out } :
              !button_n ? { 12'hfff, ste_buttons } :
              !(joyrh_n & joyrl_n) ? { joyrh_n ? 8'hff : ste_joy_in[15:8], joyrl_n ? 8'hff : ste_joy_in[7:0] } :
              mcu_dout;

// Shifter signals
wire        cmpcs_n, latch, de, blank_n, rdat_n, wdat_n, dcyc_n, sreq, sload_n, mono;
wire [15:0] shifter_dout;
wire [ 7:0] dma_snd_l, dma_snd_r;
wire [ 3:0] r, g, b;

// RAM signals
wire [23:1] ram_a;
wire        ram_uds, ram_lds, ram_we_n;
wire [15:0] ram_din;

// combined bus signals
wire        fc0 = blitter_has_bus ? blitter_fc0 : cpu_fc0;
wire        fc1 = blitter_has_bus ? blitter_fc1 : cpu_fc1;
wire        fc2 = blitter_has_bus ? blitter_fc2 : cpu_fc2;
wire        as_n = blitter_has_bus ? blitter_as_n : cpu_as_n;
wire        rw = blitter_has_bus ? blitter_rw_n : cpu_rw;
wire        uds_n = blitter_has_bus ? blitter_ds_n : cpu_uds_n;
wire        lds_n = blitter_has_bus ? blitter_ds_n : cpu_lds_n;
wire [23:1] mbus_a = blitter_has_bus ? blitter_addr : cpu_a;
// dout from the current bus master - TODO: merge with cpu_din after adding output enables to GSTMCU
wire [15:0] mbus_dout = !rdat_n ? shifter_dout :
                        !rom_n   ? rom_data :
                        blitter_sel ? blitter_data_out :
                        ~rdy_i ? dma_data_out :
                        cpu_dout;

wire        dtack_n = mcu_dtack_n_adj & ~mfp_dtack & ~mste_ctrl_sel & ~vme_sel & ~rtc_sel & blitter_dtack_n;

/* ------------------------------------------------------------------------------ */
/* ------------------------------ GSTMCU + Shifter ------------------------------ */
/* ------------------------------------------------------------------------------ */

wire pal;
gstmcu gstmcu (
	.clk32      ( clk_32 ),
	.resb       ( ~reset ),
	.porb       ( ~init ),
	.FC0        ( fc0 ),
	.FC1        ( fc1 ),
	.FC2        ( fc2 ),
	.AS_N       ( as_n ),
	.RW         ( rw ),
	.UDS_N      ( uds_n ),
	.LDS_N      ( lds_n ),
	.VMA_N      ( vma_n ),
	.MFPINT_N   ( mfpint_n ),
	.A          ( mbus_a ), // from CPU bus
	.ADDR       ( ram_a ),  // to RAM
	// DIN - only interested in sources which can be bus masters (+shifter) - to avoid long combinatorial paths
	.DIN        ( ~rdy_i ? dma_data_out : blitter_sel ? blitter_data_out : !rdat_n  ? shifter_dout : cpu_dout ),
	.DOUT       ( mcu_dout ),
	.CLK_O      ( clk16 ),
	.MHZ8       ( mhz8 ),
	.MHZ8_EN1   ( mhz8_en1 ),
	.MHZ8_EN2   ( mhz8_en2 ),
	.MHZ4       ( mhz4 ),
	.MHZ4_EN    ( mhz4_en ),
	.RDY_N_I    ( rdy_o ),
	.RDY_N_O    ( rdy_i ),
	.BG_N       ( mcu_bg_n ),
	.BR_N_I     ( blitter_br_n ),
	.BR_N_O     ( mcu_br_n ),
	.BGACK_N_I  ( 1'b1 ),
	.BGACK_N_O  ( mcu_bgack_n ),
	.BERR_N     ( berr_n ),
	.IPL0_N     ( ipl0_n ),
	.IPL1_N     ( ipl1_n ),
	.IPL2_N     ( ipl2_n ),
	.DTACK_N_I  ( dtack_n ),
	.DTACK_N_O  ( mcu_dtack_n ),
	.IACK_N     ( mfpiack_n),
	.ROM0_N     ( rom0_n ),
	.ROM1_N     ( rom1_n ),
	.ROM2_N     ( rom2_n ),
	.ROM3_N     ( rom3_n ),
	.ROM4_N     ( rom4_n ),
	.ROM5_N     ( rom5_n ),
	.ROM6_N     ( rom6_n ),
	.ROMP_N     ( romp_n ),
	.RAM_N      ( ),
	.RAS0_N     ( ras0_n ),
	.RAS1_N     ( ras1_n ),
	.RAM_LDS    ( ram_lds ),
	.RAM_UDS    ( ram_uds ),
	.VPA_N      ( vpa_n ),
	.MFPCS_N    ( mfpcs_n ),
	.SNDIR      ( sndir ),
	.SNDCS      ( sndcs ),
	.N6850      ( n6850 ),
	.FCS_N      ( fcs_n ),
	.RTCCS_N    ( rtccs_n ),
	.RTCRD_N    ( rtcrd_n ),
	.RTCWR_N    ( rtcwr_n ),
	.LATCH      ( latch ),
	.HSYNC_N    ( hsync_n ),
	.VSYNC_N    ( vsync_n ),
	.DE         ( de ),
	.BLANK_N    ( blank_n ),
	.PAL        ( pal ),
	.MDE60      ( mde60 ),
	.RDAT_N     ( rdat_n ),
	.WE_N       ( ram_we_n ),
	.WDAT_N     ( wdat_n ),
	.CMPCS_N    ( cmpcs_n ),
	.DCYC_N     ( dcyc_n ),
	.SREQ       ( sreq),
	.SLOAD_N    ( sload_n),
	.SINT       ( sint ),

	.BUTTON_N   ( button_n ),
	.JOYWE_N    ( joywe_n  ),
	.JOYRL_N    ( joyrl_n  ),
	.JOYWL      ( joywl    ),
	.JOYRH_N    ( joyrh_n  ),

	.st            ( ~ste ),
	.extra_ram     ( MEM8M | MEM14M ),
	.tos192k       ( tos192k ),
	.turbo         ( turbo_bus ),
	.viking_at_c0  ( viking_enable && !steroids ),
	.viking_at_e8  ( viking_enable &&  steroids ),
	.bus_cycle     ( bus_cycle )
);

wire       ce_pix;
wire [1:0] ce_div;
gstshifter gstshifter (
	.clk32      ( clk_32 ),
	.ste        ( ste ),
	.resb       ( ~reset ),

	// CPU/RAM interface
	.CS         ( ~cmpcs_n ),
	.A          ( mbus_a[6:1] ),
	.DIN        ( mbus_dout ),
	.DOUT       ( shifter_dout ),
	.LATCH      ( latch ),
	.RDAT_N     ( rdat_n ),   // latched MDIN -> DOUT
	.WDAT_N     ( wdat_n ),   // DIN  -> MDOUT
	.RW         ( rw ),
	.MDIN       ( ram_data_out ),
	.MDOUT      ( ram_din  ),

	// VIDEO
	.MONO_OUT   ( mono ),
	.LOAD_N     ( dcyc_n ),
	.DE         ( de ),
	.BLANK_N    ( blank_n ),
	.R          ( r ),
	.G          ( g ),
	.B          ( b ),
	.CE_PIX     ( ce_pix ),
	.PIX_ACTIVE ( pix_active ),
	.CE_DIV     ( ce_div ),

	// DMA SOUND
	.SLOAD_N    ( sload_n ),
	.SREQ       ( sreq ),
	.audio_left ( dma_snd_l ),
	.audio_right( dma_snd_r )
);

// --------------- the Viking compatible 1280x1024 graphics card -----------------

// viking/sm194 is enabled and max 8MB memory may be enabled. In steroids mode
// video memory is moved to $e80000 and all stram up to 14MB may be used
wire viking_mem_ok = MEM512K || MEM1M || MEM2M || MEM4M || MEM8M;
wire viking_enable = (viking_en && viking_mem_ok) || steroids;

// check for cpu access to 0xcxxxxx with viking enabled to switch video
// output once the driver loads. 256 accesses to the viking memory range
// are considered a valid sign that the driver is working. Without driver
// others may also probe that area which is why we want to see 256 accesses
reg [7:0] viking_in_use;
reg       viking_active;

always @(posedge clk_32) begin
	if(reset) begin
		viking_in_use <= 8'h00;
		viking_active <= 1'b0;
	end else begin
		// cpu writes to $c0xxxx or $e80000
		if(mhz8_en1 && !as_n && viking_enable &&
		  (mbus_a[23:18] == (steroids?6'b111010:6'b110000)) && (viking_in_use != 8'hff))
			viking_in_use <= viking_in_use + 1'd1;

		viking_active <= (viking_in_use == 8'hff);
	end
end

wire viking_hs, viking_vs, viking_hbl, viking_vbl;
wire viking_pix;

wire [23:1] viking_vaddr;
wire viking_read;

viking viking (
	.pclk      ( clk_96          ),
	.himem     ( steroids        ),
	.bus_sync  ( mhz8_en1 & viking_cycle ), // 2 MHz bus sync

	// memory interface
	.addr      ( viking_vaddr    ), // video word address
	.read      ( viking_read     ), // video read cycle
	.data      ( ram_data_out64  ), // video data read

	// video output
	.hs        ( viking_hs       ),
	.vs        ( viking_vs       ),
	.hblank    ( viking_hbl      ),
	.vblank    ( viking_vbl      ),
	.pix       ( viking_pix      )
);

// MEGA65: 2:1 downscaling to 640x512 in the 32 MHz video clock domain
wire [7:0] viking_grey;
wire       viking_s_hs, viking_s_vs, viking_s_hbl, viking_s_vbl;

viking_scale viking_scale (
	.clk_96    ( clk_96          ),
	.in_hblank ( viking_hbl      ),
	.in_vblank ( viking_vbl      ),
	.in_vs     ( viking_vs       ),
	.in_pix    ( viking_pix      ),

	.clk_32    ( clk_32          ),
	.grey      ( viking_grey     ),
	.hs        ( viking_s_hs     ),
	.vs        ( viking_s_vs     ),
	.hblank    ( viking_s_hbl    ),
	.vblank    ( viking_s_vbl    )
);

/* ------------------------------------------------------------------------------ */
/* ------------------------------------ CPU ------------------------------------- */
/* ------------------------------------------------------------------------------ */

reg         use_16mhz;
reg         turbo_bus;

always @(posedge clk_32)
	if (mhz8_en1 & as_n) begin
		use_16mhz <= (enable_16mhz | steroids);
		turbo_bus <= (enable_cache | steroids);
	end

wire        fx68_phi1 = use_16mhz ?  clk16_en : mhz8_en1;
wire        fx68_phi2 = use_16mhz ? ~clk16_en : mhz8_en2;

wire        shifter_cycle = (turbo_bus && (bus_cycle == 0 || bus_cycle == 3)) || (!turbo_bus && bus_cycle == 2);
wire        mcu_dtack_n_adj = (use_16mhz & ~rom_n) ? (mcu_dtack_n | shifter_cycle) : mcu_dtack_n;

fx68k fx68k (
	.clk        ( clk_32     ),
	.HALTn      ( 1'b1       ),
	.extReset   ( reset      ),
	.pwrUp      ( reset      ),
	.enPhi1     ( fx68_phi1 | reset ),
	.enPhi2     ( fx68_phi2 | reset ),

	.eRWn       ( cpu_rw ),
	.ASn        ( cpu_as_n ),
	.LDSn       ( cpu_lds_n ),
	.UDSn       ( cpu_uds_n ),
	.E          ( cpu_E ),
	.VMAn       ( vma_n ),
	.FC0        ( cpu_fc0 ),
	.FC1        ( cpu_fc1 ),
	.FC2        ( cpu_fc2 ),
	.BGn        ( blitter_bg_n ),
	.oRESETn    ( cpu_reset_n_o ),
	.oHALTEDn   (),
	.DTACKn     ( dtack_n    ),
	.VPAn       ( vpa_n      ),
	.BERRn      ( berr_n     ),
	.BRn        ( blitter_br_n & mcu_br_n ),
	.BGACKn     ( blitter_bgack_n ),
	.IPL0n      ( ipl0_n     ),
	.IPL1n      ( ipl1_n     ),
	.IPL2n      ( ipl2_n     ),
	.iEdb       ( cpu_din    ),
	.oEdb       ( cpu_dout ),
	.eab        ( cpu_a )
);

/* ------------------------------------------------------------------------------ */
/* ------------------------------------ MFP ------------------------------------- */
/* ------------------------------------------------------------------------------ */

wire acia_irq = kbd_acia_irq || midi_acia_irq;

// the STE delays the xsirq by 1/250000 second before feeding it into timer_a
// 74ls164
wire      xsint = ~sint;
reg [7:0] xsint_delay;
always @(posedge clk_32 or negedge xsint) begin
	if(!xsint) xsint_delay <= 8'h00;            // async reset
	else if (clk_2_en) xsint_delay <= {xsint_delay[6:0], xsint};
end

wire xsint_delayed = xsint_delay[7];

// mfp io7 is mono_detect which in ste is xor'd with the dma sound irq
wire mfp_io7 = mono_monitor ^ (ste?xsint:1'b0);

// inputs 1,2 and 6 are outputs from an MC1489 serial receiver
// MEGA65: I0 = parallel port BUSY, I1 = RS232 DCD, I2 = RS232 CTS, I6 = RS232 RI (not connected)
wire  [7:0] mfp_gpio_in = {mfp_io7, 1'b1, !(acsi_irq | fdc_irq), !acia_irq, blitter_irq_n, UART_CTS, 1'b1, par_busy};
wire  [1:0] mfp_timer_in = {de, ste?xsint_delayed:1'b1};
wire  [7:0] mfp_data_out;
wire        mfp_dtack;

wire        usart_so, usart_rts;
wire        mfp_int;
wire        mfp_iack = ~mfpiack_n;
assign      mfpint_n = ~mfp_int;

mfp mfp (
	// cpu register interface
	.clk      ( clk_32        ),
	.clk_en   ( mhz4_en       ),
	.reset    ( peripheral_reset ),
	.din      ( mbus_dout[7:0]),
	.sel      ( ~mfpcs_n      ),
	.addr     ( mbus_a[5:1]   ),
	.ds       ( lds_n         ),
	.rw       ( rw            ),
	.dout     ( mfp_data_out  ),
	.irq      ( mfp_int       ),
	.iack     ( mfp_iack      ),
	.dtack    ( mfp_dtack     ),

	// serial/rs232 interface
	.si       ( UART_RXD      ),
	.so       ( usart_so      ),

	// input signals
	.t_i      ( mfp_timer_in  ),  // timer a/b inputs
	.i        ( mfp_gpio_in   )   // gpio-in
);

/* ------------------------------------------------------------------------------ */
/* ---------------------------------- IKBD -------------------------------------- */
/* ------------------------------------------------------------------------------ */

wire ikbd_tx, ikbd_rx;
wire joy_port_ste;

// MEGA65: bring the keyboard matrix and the joysticks into the 2 MHz domain
// (all three clocks are generated by the same MMCM)
reg [119:0] kbd_matrix_2;
reg   [5:0] joy_mouse_2;
reg   [4:0] joy_stick_2;
reg  [24:0] ps2_mouse_2;
always @(posedge clk_2) begin
	kbd_matrix_2 <= kbd_matrix;
	joy_mouse_2  <= joy_mouse;
	joy_stick_2  <= joy_stick;
	ps2_mouse_2  <= ps2_mouse;
end

ikbd ikbd (
	.clk(clk_2),
	.res(ikbd_reset),

	.ps2_key(11'd0),
	.ps2_mouse(ps2_mouse_2),
	.ps2_mouse_ext(8'd0),
	.matrix_ext(kbd_matrix_2),

	.tx(ikbd_tx),
	.rx(ikbd_rx),
	.caps_lock(),
	.joystick0(joy_port_ste ? 6'd0 : joy_mouse_2),
	.joystick1(joy_port_ste ? 5'd0 : joy_stick_2),
	.joy_port_toggle()
);

// MEGA65: the STe joypad ports are selected in the on-screen-menu (MiSTer: F11)
assign joy_port_ste = cfg_ste_pads;

/* ------------------------------------------------------------------------------ */
/* ------------------------------- keyboard ACIA -------------------------------- */
/* ------------------------------------------------------------------------------ */

wire [7:0] kbd_acia_data_out;

// MEGA65 debugging: remember the bytes the CPU reads from the keyboard ACIA's data register
wire       kbd_data_rd = n6850 & ~mbus_a[2] & mbus_a[1] & rw;
reg        kbd_data_rd_d;
reg  [7:0] kbd_data_last;
always @(posedge clk_32) begin
	kbd_data_rd_d <= kbd_data_rd;
	if (kbd_data_rd) kbd_data_last <= kbd_acia_data_out;
	if (kbd_data_rd_d & ~kbd_data_rd) dbg_kbd_bytes <= { dbg_kbd_bytes[23:0], kbd_data_last };
end
wire       kbd_acia_irq;

acia kbd_acia (
	// cpu interface
	.clk      ( clk_32             ),
	.E        ( cpu_E              ),
	.reset    ( reset              ),
	.din      ( mbus_dout[15:8]    ),
	.sel      ( n6850 & ~mbus_a[2] ),
	.rs       ( mbus_a[1]          ),
	.rw       ( rw                 ),
	.dout     ( kbd_acia_data_out  ),
	.irq      ( kbd_acia_irq       ),

	.rx       ( ikbd_tx            ),
	.tx       ( ikbd_rx            ),

	.dout_strobe ( )
);

/* ------------------------------------------------------------------------------ */
/* --------------------------------- MIDI ACIA ---------------------------------- */
/* ------------------------------------------------------------------------------ */

wire [7:0] midi_acia_data_out;
wire       midi_acia_irq;
wire       midi_tx;
assign     midi_txd = midi_tx;

acia midi_acia (
	// cpu interface
	.clk      ( clk_32             ),
	.E        ( cpu_E              ),
	.reset    ( reset              ),
	.din      ( mbus_dout[15:8]    ),
	.sel      ( n6850 & mbus_a[2]  ),
	.rs       ( mbus_a[1]          ),
	.rw       ( rw                 ),
	.dout     ( midi_acia_data_out ),
	.irq      ( midi_acia_irq      ),

	.rx       ( midi_rxd           ),
	.tx       ( midi_tx            ),

	.dout_strobe ( )
);

/* ------------------------------------------------------------------------------ */
/* ------------------------------------ PSG ------------------------------------- */
/* ------------------------------------------------------------------------------ */

wire [7:0] snd_data_out;
wire [9:0] ym_audio_out_l;
wire [9:0] ym_audio_out_r;

reg clk_2_en;
always @(posedge clk_32) begin
	reg [3:0] cnt;
	clk_2_en <= (cnt == 0);
	cnt <= cnt + 1'd1;
end

// MEGA65: the parallel port (port B, strobe = port A bit 5, busy = MFP I0) is
// available as pins, so that also "Gauntlet" style joystick adapters work
wire [7:0] port_b_in = par_din;
wire [7:0] port_a_in = port_a_out;
wire [7:0] port_a_out;
wire [7:0] port_b_out;
wire       port_b_dir;
wire       floppy_side = port_a_out[0];
wire [1:0] floppy_sel = port_a_out[2:1];
assign     usart_rts   = port_a_out[3];
assign     uart_txd    = usart_so;
assign     uart_rts    = usart_rts;
assign     uart_dtr    = port_a_out[4];
assign     par_strobe  = port_a_out[5];
assign     par_dout    = port_b_out;
assign     par_dout_en = port_b_dir;

ym2149 ym2149 (
	.CLK         ( clk_32        ),
	.CE          ( clk_2_en      ),
	.RESET       ( peripheral_reset ),
	.DI          ( mbus_dout[15:8]),
	.DO          ( snd_data_out  ),
	.AUDIO_L     ( ym_audio_out_l),
	.AUDIO_R     ( ym_audio_out_r),
	.BDIR        ( sndir         ),
	.BC          ( sndcs         ),
	.SEL         ( 1'b0          ),
	.STEREO      ( psg_stereo    ),
	.ACTIVE      (               ),
	.IOA_in      ( port_a_in     ),
	.IOA_out     ( port_a_out    ),
	.IOB_in      ( port_b_in     ),
	.IOB_out     ( port_b_out    ),
	.IOB_dir     ( port_b_dir    )
);

// audio output processing
assign audio_mix_l = {1'b0, ym_audio_out_l, ym_audio_out_l[9:5]} + {1'b0, dma_snd_l, dma_snd_l[7:1]};
assign audio_mix_r = {1'b0, ym_audio_out_r, ym_audio_out_r[9:5]} + {1'b0, dma_snd_r, dma_snd_r[7:1]};

/* ------------------------------------------------------------------------------ */
/* ------------------------------ Mega STe control ------------------------------ */
/* ------------------------------------------------------------------------------ */

// mega ste cache controller 8 bit interface at $ff8e20 - $ff8e21
// STEroids mode does not have this config, it always runs full throttle
wire       mste_ctrl_sel = !steroids && mste && iodevice && !lds_n && ({mbus_a[15:1], 1'd0} == 16'h8e20);
wire [7:0] mste_ctrl_data_out;
wire       enable_16mhz, enable_cache;

mste_ctrl mste_ctrl (
	// cpu register interface
	.clk      ( clk_32             ),
	.reset    ( reset              ),
	.din      ( mbus_dout[7:0]     ),
	.sel      ( mste_ctrl_sel      ),
	.rw       ( rw                 ),
	.dout     ( mste_ctrl_data_out ),

	.enable_cache ( enable_cache   ),
	.enable_16mhz ( enable_16mhz   )
);

// vme controller 8 bit interface at $ffff8e00 - $ffff8e0f
// (requierd to enable Mega STE cpu speed/cache control)
wire vme_sel = !steroids && mste && iodevice && ({mbus_a[15:4], 4'd0} == 16'h8e00);

/* ------------------------------------------------------------------------------ */
/* ---------------------------------- Blitter ----------------------------------- */
/* ------------------------------------------------------------------------------ */
wire        blitter_irq_n;
wire        blitter_br_n;
wire        blitter_bgack_n;
wire        blitter_bg_n;
wire        blitter_sel;
wire [15:0] blitter_data_out;

wire        blitter_as_n;
wire        blitter_ds_n;
wire        blitter_rw_n;
wire        blitter_fc0, blitter_fc1, blitter_fc2;
wire        blitter_dtack_n;
wire [23:1] blitter_addr;
wire        blitter_has_bus;

wire mblit_selected;
wire mblit_oBGACKn;

stBlitter_m65 stBlitter(
	.clk      ( clk_32 ),
	.aRESETn  ( !peripheral_reset ),
	.sReset   ( init | peripheral_reset ),
	.extReset ( 1'b0 ),
	.pwrUp    ( init ),
	.enPhi1   ( use_16mhz ?  clk16_en : mhz8_en1 ),
	.enPhi2   ( use_16mhz ? ~clk16_en : mhz8_en2 ),
	.ASn      ( as_n | ~blitter_en ),
	.RWn      ( cpu_rw ),
	.LDSn     ( lds_n ),
	.UDSn     ( uds_n ),
	.FC0      ( fc0 ),
	.FC1      ( fc1 ),
	.FC2      ( fc2 ),
	.BERRn    ( berr_n ),
	.iDTACKn  ( dtack_n ),
	.ctrlOe   ( blitter_has_bus ),
	.dataOe   ( blitter_sel ),
	.oASn     ( blitter_as_n ),
	.oDSn     ( blitter_ds_n ),
	.oRWn     ( blitter_rw_n ),
	.oDTACKn  ( blitter_dtack_n ),
	.selected ( mblit_selected ),
	.iBRn     ( mcu_br_n ),
	.BGIn     ( blitter_bg_n ),
	.iBGACKn  ( mcu_bgack_n ),
	.oBRn     ( blitter_br_n ),
	.oBGACKn  ( mblit_oBGACKn ),
	.INTn     ( blitter_irq_n ),
	.BGOn     ( mcu_bg_n ),
	.dmaInput ( mbus_dout ),
	.iABUS    ( mbus_a ),
	.oABUS    ( blitter_addr ),
	.iDBUS    ( cpu_dout ),
	.oDBUS    ( blitter_data_out )
);

assign blitter_bgack_n = mblit_oBGACKn & mcu_bgack_n;		// This really happens inside Blitter
assign { blitter_fc2, blitter_fc1, blitter_fc0} = 3'b101;

/* ------------------------------------------------------------------------------ */
/* ---------------------------- STe controller ports ---------------------------- */
/* ------------------------------------------------------------------------------ */

wire [15:0] ste_joy_in;
wire  [3:0] ste_buttons;
reg   [7:0] ste_joy_out;

wire  [7:0] ste_joy_out_pins = joywe_n ? 8'hff : ste_joy_out;

always @(posedge clk_32) begin
	if (joywl) ste_joy_out <= mbus_dout[7:0];
end

ste_joypad ste_joypad0 (
	.joy      ( joy_port_ste ? ste_pad0 : 21'd0 ),
	.din      ( ste_joy_out_pins[3:0] ),
	.dout     ( { ste_joy_in[11:8], ste_joy_in[3:0] } ),
	.buttons  ( ste_buttons[1:0] )
);

ste_joypad ste_joypad1 (
	.joy      ( joy_port_ste ? ste_pad1 : 21'd0 ),
	.din      ( ste_joy_out_pins[7:4] ),
	.dout     ( { ste_joy_in[15:12], ste_joy_in[7:4] } ),
	.buttons  ( ste_buttons[3:2] )
);

/* ------------------------------------------------------------------------------ */
/* ------------------------------------- DMA ------------------------------------ */
/* ------------------------------------------------------------------------------ */

wire [15:0] dma_data_out;

wire acsi_irq;

// MEGA65: ACSI "IO controller"
wire        dio_data_in_strobe;
wire [15:0] dio_data_in_reg;
wire        dio_data_out_strobe;
wire [15:0] dio_data_out_reg;
wire        dio_dma_ack;
wire  [7:0] dio_dma_status;
wire        dio_dma_nak;
wire  [7:0] dio_status_in;
wire  [3:0] dio_status_index;
wire  [3:0] dio_fifo_used;
wire  [1:0] hd_present;

acsi_ctrl acsi_ctrl (
	.clk                 ( clk_32              ),
	.reset               ( reset               ),

	.img_mounted         ( hd_img_mounted      ),
	.img_size            ( img_size            ),
	.img_readonly        ( img_readonly        ),
	.present             ( hd_present          ),

	.dio_data_in_strobe  ( dio_data_in_strobe  ),
	.dio_data_in_reg     ( dio_data_in_reg     ),
	.dio_data_out_strobe ( dio_data_out_strobe ),
	.dio_data_out_reg    ( dio_data_out_reg    ),
	.dio_dma_ack         ( dio_dma_ack         ),
	.dio_dma_status      ( dio_dma_status      ),
	.dio_dma_nak         ( dio_dma_nak         ),
	.dio_status_in       ( dio_status_in       ),
	.dio_status_index    ( dio_status_index    ),
	.dio_fifo_used       ( dio_fifo_used       ),

	.sd_lba              ( hd_sd_lba           ),
	.sd_rd               ( hd_sd_rd            ),
	.sd_wr               ( hd_sd_wr            ),
	.sd_ack              ( hd_sd_ack           ),
	.sd_buff_addr        ( sd_buff_addr        ),
	.sd_buff_dout        ( sd_buff_dout        ),
	.sd_buff_din         ( hd_sd_buff_din      ),
	.sd_buff_wr          ( sd_buff_wr          ),

	.led                 ( hd_led              )
);

dma dma (
	// system interface
	.clk          ( clk_32        ),
	.clk_en       ( mhz8_en1      ),
	.reset        ( reset         ),

	// cpu interface
	.cpu_din      ( mbus_dout     ),
	.cpu_sel      ( ~fcs_n        ),
	.cpu_a1       ( mbus_a[1]     ),
	.cpu_rw       ( rw            ),
	.cpu_dout     ( dma_data_out  ),

	// IO controller interface for ACSI (MEGA65: acsi_ctrl.sv)
	.dio_data_in_strobe  ( dio_data_in_strobe  ),
	.dio_data_in_reg     ( dio_data_in_reg     ),
	.dio_data_out_strobe ( dio_data_out_strobe ),
	.dio_data_out_reg    ( dio_data_out_reg    ),
	.dio_dma_ack         ( dio_dma_ack         ),
	.dio_dma_status      ( dio_dma_status      ),
	.dio_dma_nak         ( dio_dma_nak         ),
	.dio_status_in       ( dio_status_in       ),
	.dio_status_index    ( dio_status_index    ),
	.dio_fifo_used       ( dio_fifo_used       ),

	// additional signals for ACSI interface
	.acsi_irq     ( acsi_irq      ),
	.acsi_enable  ( acsi_enable   ),

	// FDC interface
	.fdc_drq      ( fdc_drq  ),
	.fdc_addr     ( fdc_addr ),
	.fdc_sel      ( fdc_sel  ),
	.fdc_rw       ( fdc_rw   ),
	.fdc_din      ( fdc_din  ),
	.fdc_dout     ( fdc_dout ),

	// ram interface
	.rdy_i        ( rdy_i        ),
	.rdy_o        ( rdy_o        ),
	.ram_din      ( shifter_dout )
);

wire       fdc_irq;
wire       fdc_drq;
wire [1:0] fdc_addr;
wire       fdc_sel;
wire       fdc_rw;
wire [7:0] fdc_din;
wire [7:0] fdc_dout;

// Some broken software selects both drives at the same time. On real hardware this
// only works if no second drive is present. In our setup the second drive is present
// but we can simply map all such broken accesses to drive A only
wire [1:0] floppy_sel_exclusive = (floppy_sel == 2'b00)?2'b10:floppy_sel;

fdc1772 #(.IMG_TYPE(1)) fdc1772 (
	.clkcpu         ( clk_32           ), // system cpu clock.
	.clk8m_en       ( mhz8_en1         ),

	// external set signals
	.floppy_drive   ( {2'b11, floppy_sel_exclusive} ),
	.floppy_side    ( floppy_side      ),
	.floppy_reset   ( ~peripheral_reset),
	.floppy_step    (                  ),
	.floppy_motor   ( 1'b0             ),
	.floppy_ready   (                  ),

	// interrupts
	.irq            ( fdc_irq          ),
	.drq            ( fdc_drq          ),

	.cpu_addr       ( fdc_addr         ),
	.cpu_sel        ( fdc_sel          ),
	.cpu_rw         ( fdc_rw           ),
	.cpu_din        ( fdc_din          ),
	.cpu_dout       ( fdc_dout         ),

	// place any signals that need to be passed up to the top after here.
	.img_mounted    ( img_mounted      ), // signaling that new image has been mounted
	.img_wp         ( fdc_wp           ), // write protect (MEGA65: includes read-only images, per drive)
	.img_ds         ( 1'b0             ),
	.img_size       ( img_size         ), // size of image in bytes
	.sd_lba         ( sd_lba           ),
	.sd_rd          ( sd_rd            ),
	.sd_wr          ( sd_wr            ),
	.sd_ack         ( sd_ack           ),
	.sd_buff_addr   ( sd_buff_addr     ),
	.sd_dout        ( sd_buff_dout     ),
	.sd_din         ( sd_buff_din      ),
	.sd_dout_strobe ( sd_buff_wr       )
);

/* ------------------------------------------------------------------------------ */
/* ------------------------ Mega ST real time clock (MEGA65) --------------------- */
/* ------------------------------------------------------------------------------ */
// MEGA65: the RP5C15 of the Mega ST at $FFFC21 - $FFFC3F, fed by the MEGA65's RTC.
// The GSTMCU does not acknowledge this range (a plain ST gives a bus error there).
assign rtc_sel = iodevice && !lds_n && (mbus_a[15:5] == {8'hFC, 3'b001});

rp5c15_m65 rp5c15 (
	.clk  ( clk_32           ),
	.reset( peripheral_reset ),
	.sel  ( rtc_sel          ),
	.rw   ( rw               ),
	.addr ( mbus_a[4:1]      ),
	.din  ( mbus_dout[3:0]   ),
	.dout ( rtc_data_out     ),
	.rtc  ( rtc              )
);

/* ------------------------------------------------------------------------------ */
/* ------------------------------- Cubase dongle  ------------------------------- */
/* ------------------------------------------------------------------------------ */
wire        cubase3_d8;
wire  [7:0] cubase2_dout;
wire  [7:0] cubase_dout = cubase_sel ? cubase2_dout : {7'h7f, cubase3_d8};
reg         cubase_sel; // Cubase3/2 dongle
reg         cubase_lock;

always @(posedge clk_32) begin
	if (peripheral_reset) begin
		cubase_sel <= 0;
		cubase_lock <= 0;
	end
	else if (cubase_enable & !rom3_n & !cubase_lock) begin
		cubase_sel <= |mbus_a[7:1];
		cubase_lock <= 1;
	end
end

cubase2_dongle cubase2_dongle (
	.clk        ( clk_32           ),
	.reset      ( peripheral_reset ),
	.uds_n      ( uds_n            ),
	.A          ( mbus_a[8:1]      ),
	.D          ( cubase2_dout     )
);

cubase3_dongle cubase3_dongle (
	.clk        ( clk_32           ),
	.reset      ( peripheral_reset ),
	.rom3_n     ( rom3_n           ),
	.a8         ( mbus_a[8]        ),
	.d8         ( cubase3_d8       )
);

/* ------------------------------------------------------------------------------ */
/* --------------------------- SDRAM bus multiplexer ---------------------------- */
/* ------------------------------------------------------------------------------ */

wire cpu_precycle = (bus_cycle == 0);
wire cpu_cycle    = (bus_cycle == 1) || (bus_cycle == 2 && turbo_bus);
wire viking_cycle = (bus_cycle == 2 && !turbo_bus) || (bus_cycle == 3 && turbo_bus); // this is the shifter cycle, too

reg ras_n_d;
reg data_wr;
wire ram_req = ras_n_d & ~ras_n & |ram_a; // RAS_N going low and not refresh
wire ram_we = ~ram_we_n;

// TOS upload via the M2M ROM loader
reg tos192k = 1'b0;
reg dio_data_in_strobe_uioD;
assign dio_strobe_ack = dio_data_in_strobe_uioD;

always @(posedge clk_32) begin
	ras_n_d <= ras_n;
	data_wr <= 1'b0;
	if (cpu_precycle && mhz8_en1) begin
		dio_data_in_strobe_uioD <= dio_strobe;
		if (dio_strobe ^ dio_data_in_strobe_uioD) data_wr <= 1'b1;
	end
	if (dio_download) tos192k <= tos192k_in;
end

// ----------------- RAM address --------------
wire [23:1] sdram_address = (cpu_cycle & dio_download) ? dio_addr[23:1] :
                            (viking_cycle & viking_active & viking_read) ? viking_vaddr : ram_a;

wire        ram_en = (MEM512K & ram_a[23:19] == 5'b00000) ||
                     (MEM1M   & ram_a[23:20] == 4'b0000)  ||
                     (MEM2M   & ram_a[23:21] == 3'b000)   ||
                     (MEM4M   & ram_a[23:22] == 2'b00)    ||
                     (MEM8M   & ram_a[23] == 1'b0)        ||
                     (MEM14M  & (~ram_a[23] | ~ram_a[22] | (ram_a[23] & ram_a[22] & ~ram_a[21]))) ||
                     (viking_enable & ~steroids & ram_a[23:18] == 6'b110000) ||
                     (viking_enable &  steroids & ram_a[23:19] == 5'b11101);

// ----------------- RAM read -----------------
wire sdram_req = (cpu_cycle & dio_download) ? data_wr :
                 (viking_cycle & viking_active & viking_read) ? 1'b1 :
                 (ram_req & ram_en);

// ----------------- RAM write -----------------
wire sdram_we = (cpu_cycle & dio_download) ? 1'b1 : ram_we;

wire [15:0] ram_data_in = dio_download ? dio_data : ram_din;

// data strobe
wire sdram_uds = (cpu_cycle & dio_download) ? 1'b1 : ram_uds;
wire sdram_lds = (cpu_cycle & dio_download) ? 1'b1 : ram_lds;

// MEGA65: the TOS image is always stored at $E00000, no matter if it is a
// 192k TOS (visible at $FC0000) or a 256k TOS (visible at $E00000)
wire [23:1] rom_a = (!rom2_n)              ? { 4'hE, 2'b00, mbus_a[17:1] } :
                    !rom4_n                ? { 8'hFA,       mbus_a[15:1] } :
                    !rom3_n                ? { 8'hFB,       mbus_a[15:1] } : mbus_a;

wire [15:0] ram_data_out;
wire [63:0] ram_data_out64;
wire [15:0] rom_data_out;

generate
if (BRAM_MEM) begin : g_bram
	// MEGA65 R3/R3A: no SDRAM
	assign sdram_clk   = 1'b0;
	assign sdram_cke   = 1'b0;
	assign sdram_ras_n = 1'b1;
	assign sdram_cas_n = 1'b1;
	assign sdram_we_n  = 1'b1;
	assign sdram_cs_n  = 1'b1;
	assign sdram_ba    = 2'b00;
	assign sdram_a     = 13'd0;
	assign sdram_dqml  = 1'b0;
	assign sdram_dqmh  = 1'b0;
	assign sdram_dq    = 16'hZZZZ;

	bram_m65 bram (
		.clk_96        ( clk_96                   ),
		.clk_8_en      ( mhz8_en1                 ),

		// cpu/chipset interface
		.din           ( ram_data_in              ),
		.addr          ( { 1'b0, sdram_address }  ),
		.ds            ( { sdram_uds, sdram_lds } ),
		.req           ( sdram_req                ),
		.we            ( sdram_we                 ),
		.dout          ( ram_data_out             ),
		.dout64        ( ram_data_out64           ),

		// ROM access port
		.rom_oe        ( ~rom_n                   ),
		.rom_addr      ( { 1'b0, rom_a }          ),
		.rom_dout      ( rom_data_out             )
	);
end else begin : g_sdram
	assign sdram_cke = 1'b1;

	sdram_m65 sdram (
		// interface to the IS42S16320F chip
		.sd_data     	( sdram_dq                   ),
		.sd_addr     	( sdram_a                    ),
		.sd_dqm      	( {sdram_dqmh, sdram_dqml}   ),
		.sd_cs       	( sdram_cs_n                 ),
		.sd_ba       	( sdram_ba                   ),
		.sd_we       	( sdram_we_n                 ),
		.sd_ras      	( sdram_ras_n                ),
		.sd_cas      	( sdram_cas_n                ),
		.sd_clk      	( sdram_clk                  ),

		// system interface
		.clk_96        ( clk_96                   ),
		.clk_8_en      ( mhz8_en1                 ),
		.init          ( init                     ),

		// cpu/chipset interface
		.din           ( ram_data_in              ),
		.addr          ( { 1'b0, sdram_address }  ),
		.ds            ( { sdram_uds, sdram_lds } ),
		.req           ( sdram_req                ),
		.we            ( sdram_we                 ),
		.dout          ( ram_data_out             ),
		.dout64        ( ram_data_out64           ),

		// ROM access port
		.rom_oe        ( ~rom_n                   ),
		.rom_addr      ( { 1'b0, rom_a }          ),
		.rom_dout      ( rom_data_out             )
	);
end
endgenerate

endmodule
