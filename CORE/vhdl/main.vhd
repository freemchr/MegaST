----------------------------------------------------------------------------------
-- Atari ST/STe for MEGA65
--
-- Wrapper for the MiSTer core that runs exclusively in the core's clock domanin
--
-- MiSTer2MEGA65 done by sy2002 and MJoergen in 2022 and licensed under GPL v3
-- Atari ST port 2026, licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.video_modes_pkg.all;
use work.globals.all;

entity main is
   generic (
      G_VDNUM                 : natural                     -- amount of virtual drives
   );
   port (
      clk_main_i              : in  std_logic;              -- 32.083 MHz
      clk_sdram_i             : in  std_logic;              -- 96.25 MHz, phase aligned to clk_main_i
      clk_ikbd_i              : in  std_logic;              --  2.005 MHz, phase aligned to clk_main_i
      reset_soft_i            : in  std_logic;
      reset_hard_i            : in  std_logic;
      pause_i                 : in  std_logic;
      init_i                  : in  std_logic;              -- clocks not stable, yet (power on reset)

      -- MiSTer core main clock speed:
      -- Make sure you pass very exact numbers here, because they are used for avoiding clock drift at derived clocks
      clk_main_speed_i        : in  natural;

      -- Atari ST configuration
      st_mem_i                : in  std_logic_vector(2 downto 0);  -- 0=512K, 1=1M, 2=2M, 3=4M, 4=8M, 5=14M
      st_ste_i                : in  std_logic;
      st_mste_i               : in  std_logic;
      st_blitter_i            : in  std_logic;
      st_mono_i               : in  std_logic;
      st_mono60_i             : in  std_logic;              -- monochrome monitor: 60 Hz instead of 71 Hz
      st_full_border_i        : in  std_logic;              -- show the full borders (overscan)
      st_psg_stereo_i         : in  std_logic;
      st_fdc_wp_i             : in  std_logic_vector(1 downto 0);
      st_joy_swap_i           : in  std_logic;
      st_viking_i             : in  std_logic;
      st_ste_pads_i           : in  std_logic;
      st_mouse1351_i          : in  std_logic;              -- MEGA65 port 1: Commodore 1351 mouse
      st_pmod_i               : in  std_logic;              -- serial port, MIDI and printer port on the PMODs
      st_cubase_i             : in  std_logic;              -- Cubase 2/3 dongle in the cartridge port

      -- MEGA65 real time clock (M2M format), used by the Mega ST RTC (rp5c15_m65.sv)
      rtc_i                   : in  std_logic_vector(64 downto 0);

      -- TOS loader
      dio_addr_i              : in  std_logic_vector(23 downto 1);
      dio_data_i              : in  std_logic_vector(15 downto 0);
      dio_strobe_i            : in  std_logic;
      dio_strobe_ack_o        : out std_logic;
      tos192k_i               : in  std_logic;
      cart_loaded_i           : in  std_logic;
      cart_loading_i          : in  std_logic;              -- keep the ST in reset while a cartridge is loaded
      tos_loading_i           : in  std_logic;              -- keep the ST in reset while a TOS (menu) is loaded

      -- Floppy drives (MiSTer "SD" interface of fdc1772.sv)
      -- Floppy drives (0, 1) and hard disks (2, 3): MiSTer "SD" interface of fdc1772.sv and acsi_ctrl.sv
      img_mounted_i           : in  std_logic_vector(3 downto 0);
      img_readonly_i          : in  std_logic;
      img_size_i              : in  std_logic_vector(31 downto 0);
      sd_lba_o                : out std_logic_vector(4 * 32 - 1 downto 0);   -- drive i: bits 32*i+31 .. 32*i
      sd_rd_o                 : out std_logic_vector(3 downto 0);
      sd_wr_o                 : out std_logic_vector(3 downto 0);
      sd_ack_i                : in  std_logic_vector(3 downto 0);
      sd_buff_addr_i          : in  std_logic_vector(7 downto 0);
      sd_buff_dout_i          : in  std_logic_vector(15 downto 0);
      sd_buff_din_o           : out std_logic_vector(4 * 16 - 1 downto 0);   -- drive i: bits 16*i+15 .. 16*i
      sd_buff_wr_i            : in  std_logic;
      floppy_led_o            : out std_logic;
      hd_led_o                : out std_logic;

      -- Video output
      video_ce_o              : out std_logic;
      video_ce_ovl_o          : out std_logic;
      video_red_o             : out std_logic_vector(7 downto 0);
      video_green_o           : out std_logic_vector(7 downto 0);
      video_blue_o            : out std_logic_vector(7 downto 0);
      video_vs_o              : out std_logic;
      video_hs_o              : out std_logic;
      video_hblank_o          : out std_logic;
      video_vblank_o          : out std_logic;
      video_31khz_o           : out std_logic;              -- 71 Hz monochrome mode or Viking: no scandoubler

      -- Audio output (Signed PCM)
      audio_left_o            : out signed(15 downto 0);
      audio_right_o           : out signed(15 downto 0);

      -- M2M Keyboard interface
      kb_key_num_i            : in  integer range 0 to 79;    -- cycles through all MEGA65 keys
      kb_key_pressed_n_i      : in  std_logic;                -- low active: debounced feedback: is kb_key_num_i pressed right now?

      -- MEGA65 joysticks and paddles/mouse/potentiometers
      joy_1_up_n_i            : in  std_logic;
      joy_1_down_n_i          : in  std_logic;
      joy_1_left_n_i          : in  std_logic;
      joy_1_right_n_i         : in  std_logic;
      joy_1_fire_n_i          : in  std_logic;

      joy_2_up_n_i            : in  std_logic;
      joy_2_down_n_i          : in  std_logic;
      joy_2_left_n_i          : in  std_logic;
      joy_2_right_n_i         : in  std_logic;
      joy_2_fire_n_i          : in  std_logic;

      pot1_x_i                : in  std_logic_vector(7 downto 0);
      pot1_y_i                : in  std_logic_vector(7 downto 0);
      pot2_x_i                : in  std_logic_vector(7 downto 0);
      pot2_y_i                : in  std_logic_vector(7 downto 0);

      -- PMOD pins (synchronized inputs, outputs, output enables): 0..3 = PMOD1 lo, 4..7 = PMOD1 hi,
      -- 8..11 = PMOD2 lo, 12..15 = PMOD2 hi. See README.md for the pin assignment.
      pmod_in_i               : in  std_logic_vector(15 downto 0);
      pmod_out_o              : out std_logic_vector(15 downto 0);
      pmod_oe_o               : out std_logic_vector(15 downto 0);

      -- SDRAM (MEGA65 R4/R5/R6)
      sdram_clk_o             : out   std_logic;
      sdram_cke_o             : out   std_logic;
      sdram_ras_n_o           : out   std_logic;
      sdram_cas_n_o           : out   std_logic;
      sdram_we_n_o            : out   std_logic;
      sdram_cs_n_o            : out   std_logic;
      sdram_ba_o              : out   std_logic_vector(1 downto 0);
      sdram_a_o               : out   std_logic_vector(12 downto 0);
      sdram_dqml_o            : out   std_logic;
      sdram_dqmh_o            : out   std_logic;
      sdram_dq_io             : inout std_logic_vector(15 downto 0)
   );
end entity main;

architecture synthesis of main is

component atarist_m65 is
   port (
      clk_32          : in    std_logic;
      clk_96          : in    std_logic;
      clk_2           : in    std_logic;
      init            : in    std_logic;
      reset_in        : in    std_logic;

      cfg_mem         : in    std_logic_vector(2 downto 0);
      cfg_ste         : in    std_logic;
      cfg_mste        : in    std_logic;
      cfg_blitter     : in    std_logic;
      cfg_mono        : in    std_logic;
      cfg_psg_stereo  : in    std_logic;
      cfg_narrow_brd  : in    std_logic;
      cfg_mde60       : in    std_logic;
      cfg_fdc_wp      : in    std_logic_vector(1 downto 0);
      cfg_viking      : in    std_logic;
      cfg_ste_pads    : in    std_logic;
      cfg_cubase      : in    std_logic;
      rtc             : in    std_logic_vector(64 downto 0);

      dio_download    : in    std_logic;
      dio_addr        : in    std_logic_vector(23 downto 1);
      dio_data        : in    std_logic_vector(15 downto 0);
      dio_strobe      : in    std_logic;
      dio_strobe_ack  : out   std_logic;
      tos192k_in      : in    std_logic;
      cart_loaded     : in    std_logic;

      img_mounted     : in    std_logic_vector(1 downto 0);
      img_readonly    : in    std_logic;
      img_size        : in    std_logic_vector(31 downto 0);
      sd_lba          : out   std_logic_vector(31 downto 0);
      sd_rd           : out   std_logic_vector(1 downto 0);
      sd_wr           : out   std_logic_vector(1 downto 0);
      sd_ack          : in    std_logic;
      sd_buff_addr    : in    std_logic_vector(7 downto 0);
      sd_buff_dout    : in    std_logic_vector(15 downto 0);
      sd_buff_din     : out   std_logic_vector(15 downto 0);
      sd_buff_wr      : in    std_logic;

      hd_img_mounted  : in    std_logic_vector(1 downto 0);
      hd_sd_lba       : out   std_logic_vector(31 downto 0);
      hd_sd_rd        : out   std_logic_vector(1 downto 0);
      hd_sd_wr        : out   std_logic_vector(1 downto 0);
      hd_sd_ack       : in    std_logic_vector(1 downto 0);
      hd_sd_buff_din  : out   std_logic_vector(15 downto 0);

      kbd_matrix      : in    std_logic_vector(119 downto 0);
      joy_mouse       : in    std_logic_vector(5 downto 0);
      joy_stick       : in    std_logic_vector(4 downto 0);
      ste_pad0        : in    std_logic_vector(20 downto 0);
      ste_pad1        : in    std_logic_vector(20 downto 0);
      ps2_mouse       : in    std_logic_vector(24 downto 0);

      uart_rxd        : in    std_logic;
      uart_txd        : out   std_logic;
      uart_cts        : in    std_logic;
      uart_rts        : out   std_logic;
      uart_dtr        : out   std_logic;
      midi_rxd        : in    std_logic;
      midi_txd        : out   std_logic;
      par_din         : in    std_logic_vector(7 downto 0);
      par_dout        : out   std_logic_vector(7 downto 0);
      par_dout_en     : out   std_logic;
      par_strobe      : out   std_logic;
      par_busy        : in    std_logic;

      video_r         : out   std_logic_vector(7 downto 0);
      video_g         : out   std_logic_vector(7 downto 0);
      video_b         : out   std_logic_vector(7 downto 0);
      video_hs        : out   std_logic;
      video_vs        : out   std_logic;
      video_hblank    : out   std_logic;
      video_vblank    : out   std_logic;
      video_ce        : out   std_logic;
      video_31khz     : out   std_logic;

      audio_l         : out   std_logic_vector(15 downto 0);
      audio_r         : out   std_logic_vector(15 downto 0);

      floppy_led      : out   std_logic;
      hd_led          : out   std_logic;

      sdram_clk       : out   std_logic;
      sdram_cke       : out   std_logic;
      sdram_ras_n     : out   std_logic;
      sdram_cas_n     : out   std_logic;
      sdram_we_n      : out   std_logic;
      sdram_cs_n      : out   std_logic;
      sdram_ba        : out   std_logic_vector(1 downto 0);
      sdram_a         : out   std_logic_vector(12 downto 0);
      sdram_dqml      : out   std_logic;
      sdram_dqmh      : out   std_logic;
      sdram_dq        : inout std_logic_vector(15 downto 0)
   );
end component atarist_m65;

signal reset_core     : std_logic;
signal st_matrix_n    : std_logic_vector(119 downto 0);

-- joysticks: MEGA65 port 1 is the ST's port 0 (mouse port) and MEGA65 port 2 is the
-- ST's port 1 (joystick port) unless swapped; the ST's pins 1-4 and 6 are identical to
-- the MEGA65's (Commodore/Atari standard), so an Atari ST mouse works in port 1.
signal port1          : std_logic_vector(4 downto 0);   -- high active: fire, right, left, down, up
signal port2          : std_logic_vector(4 downto 0);
signal joy_mouse      : std_logic_vector(5 downto 0);
signal joy_stick      : std_logic_vector(4 downto 0);

signal ste_pad0       : std_logic_vector(20 downto 0);
signal ste_pad1       : std_logic_vector(20 downto 0);
signal ps2_mouse      : std_logic_vector(24 downto 0);

signal uart_rxd       : std_logic;
signal uart_txd       : std_logic;
signal uart_cts       : std_logic;
signal uart_rts       : std_logic;
signal uart_dtr       : std_logic;
signal midi_rxd       : std_logic;
signal midi_txd       : std_logic;
signal par_din        : std_logic_vector(7 downto 0);
signal par_dout       : std_logic_vector(7 downto 0);
signal par_dout_en    : std_logic;
signal par_strobe     : std_logic;
signal par_busy       : std_logic;

signal audio_l        : std_logic_vector(15 downto 0);
signal hd_lba         : std_logic_vector(31 downto 0);
signal hd_buff_din    : std_logic_vector(15 downto 0);

-- MEGA65 joystick port (fire, right, left, down, up) to STe joypad bits (fire, up, down, left, right)
function ste_bits(p : std_logic_vector(4 downto 0)) return std_logic_vector is
begin
   return p(4) & p(0) & p(1) & p(2) & p(3);
end function ste_bits;
signal audio_r        : std_logic_vector(15 downto 0);

begin

   -- long and short press of the reset button mean the same: reset the ST.
   -- The M2M firmware keeps the core in reset while the TOS image is being loaded.
   reset_core <= reset_soft_i or reset_hard_i or cart_loading_i or tos_loading_i;

   port1 <= not (joy_1_fire_n_i & joy_1_right_n_i & joy_1_left_n_i & joy_1_down_n_i & joy_1_up_n_i);
   port2 <= not (joy_2_fire_n_i & joy_2_right_n_i & joy_2_left_n_i & joy_2_down_n_i & joy_2_up_n_i);

   -- In the 1351 mouse mode, MEGA65 port 1 is used as mouse (via the IKBD's PS/2 mouse emulation),
   -- so the ST's mouse port does not see the raw port 1 signals.
   joy_mouse <= (others => '0') when st_mouse1351_i = '1' else
                '0' & port2     when st_joy_swap_i = '1' else
                '0' & port1;
   joy_stick <= port2           when st_mouse1351_i = '1' else
                port1           when st_joy_swap_i = '1' else
                port2;

   -- STe joypads (see ste_joypad.v): bit 0 = right, 1 = left, 2 = down, 3 = up, 4 = A (fire).
   -- Joypad A (the first one) is MEGA65 port 2, just like the ST's joystick port.
   ste_pad0 <= (20 downto 5 => '0') & ste_bits(port1) when st_joy_swap_i = '1' else (20 downto 5 => '0') & ste_bits(port2);
   ste_pad1 <= (20 downto 5 => '0') & ste_bits(port2) when st_joy_swap_i = '1' else (20 downto 5 => '0') & ste_bits(port1);

   i_mouse1351 : entity work.mouse1351
      generic map (
         G_CLK_SPEED    => CORE_CLK_SPEED
      )
      port map (
         clk_i          => clk_main_i,
         enable_i       => st_mouse1351_i,
         pot_x_n_i      => pot1_x_i,
         pot_y_n_i      => pot1_y_i,
         fire_n_i       => joy_1_fire_n_i,
         up_n_i         => joy_1_up_n_i,
         ps2_mouse_o    => ps2_mouse
      ); -- i_mouse1351

   ---------------------------------------------------------------------------------------------
   -- PMOD: serial port, MIDI and parallel port
   --
   --    PMOD1 lo: 0 = RS232 CTS (in), 1 = RS232 TXD (out), 2 = RS232 RXD (in), 3 = RS232 RTS (out)
   --    PMOD1 hi: 4 = MIDI OUT (out), 5 = MIDI IN (in), 6 = printer STROBE (out), 7 = printer BUSY (in)
   --    PMOD2:    8..15 = printer data D0..D7 (bidirectional)
   --
   -- All signals are 3.3V TTL levels: The serial port needs a MAX3232 (or a USB serial adapter),
   -- MIDI needs the usual opto-coupler/driver circuit.
   ---------------------------------------------------------------------------------------------

   uart_cts  <= pmod_in_i(0) when st_pmod_i = '1' else '1';
   uart_rxd  <= pmod_in_i(2) when st_pmod_i = '1' else '1';
   midi_rxd  <= pmod_in_i(5) when st_pmod_i = '1' else '1';
   par_busy  <= pmod_in_i(7) when st_pmod_i = '1' else '1';
   par_din   <= pmod_in_i(15 downto 8) when st_pmod_i = '1' else x"FF";

   pmod_out_o <= par_dout & par_busy & par_strobe & midi_rxd & midi_txd & uart_rts & uart_rxd & uart_txd & uart_cts;
   pmod_oe_o  <= (15 downto 8 => par_dout_en and st_pmod_i) &
                 '0' & st_pmod_i & '0' & st_pmod_i &
                 st_pmod_i & '0' & st_pmod_i & '0';

   i_atarist : atarist_m65
      port map (
         clk_32          => clk_main_i,
         clk_96          => clk_sdram_i,
         clk_2           => clk_ikbd_i,
         init            => init_i,
         reset_in        => reset_core,

         cfg_mem         => st_mem_i,
         cfg_ste         => st_ste_i,
         cfg_mste        => st_mste_i,
         cfg_blitter     => st_blitter_i,
         cfg_mono        => st_mono_i,
         cfg_psg_stereo  => st_psg_stereo_i,
         cfg_narrow_brd  => not st_full_border_i,
         cfg_mde60       => st_mono60_i,
         cfg_fdc_wp      => st_fdc_wp_i,
         cfg_viking      => st_viking_i,
         cfg_ste_pads    => st_ste_pads_i,
         cfg_cubase      => st_cubase_i,
         rtc             => rtc_i,

         -- the TOS image is only written while the core is held in reset
         dio_download    => reset_core,
         dio_addr        => dio_addr_i,
         dio_data        => dio_data_i,
         dio_strobe      => dio_strobe_i,
         dio_strobe_ack  => dio_strobe_ack_o,
         tos192k_in      => tos192k_i,
         cart_loaded     => cart_loaded_i,

         img_mounted     => img_mounted_i(1 downto 0),
         img_readonly    => img_readonly_i,
         img_size        => img_size_i,
         sd_lba          => sd_lba_o(31 downto 0),
         sd_rd           => sd_rd_o(1 downto 0),
         sd_wr           => sd_wr_o(1 downto 0),
         sd_ack          => sd_ack_i(0) or sd_ack_i(1),
         sd_buff_addr    => sd_buff_addr_i,
         sd_buff_dout    => sd_buff_dout_i,
         sd_buff_din     => sd_buff_din_o(15 downto 0),
         sd_buff_wr      => sd_buff_wr_i,

         hd_img_mounted  => img_mounted_i(3 downto 2),
         hd_sd_lba       => hd_lba,
         hd_sd_rd        => sd_rd_o(3 downto 2),
         hd_sd_wr        => sd_wr_o(3 downto 2),
         hd_sd_ack       => sd_ack_i(3 downto 2),
         hd_sd_buff_din  => hd_buff_din,

         kbd_matrix      => st_matrix_n,
         joy_mouse       => joy_mouse,
         joy_stick       => joy_stick,
         ste_pad0        => ste_pad0,
         ste_pad1        => ste_pad1,
         ps2_mouse       => ps2_mouse,

         uart_rxd        => uart_rxd,
         uart_txd        => uart_txd,
         uart_cts        => uart_cts,
         uart_rts        => uart_rts,
         uart_dtr        => uart_dtr,
         midi_rxd        => midi_rxd,
         midi_txd        => midi_txd,
         par_din         => par_din,
         par_dout        => par_dout,
         par_dout_en     => par_dout_en,
         par_strobe      => par_strobe,
         par_busy        => par_busy,

         video_r         => video_red_o,
         video_g         => video_green_o,
         video_b         => video_blue_o,
         video_hs        => video_hs_o,
         video_vs        => video_vs_o,
         video_hblank    => video_hblank_o,
         video_vblank    => video_vblank_o,
         video_ce        => video_ce_o,
         video_31khz     => video_31khz_o,

         audio_l         => audio_l,
         audio_r         => audio_r,

         floppy_led      => floppy_led_o,
         hd_led          => hd_led_o,

         sdram_clk       => sdram_clk_o,
         sdram_cke       => sdram_cke_o,
         sdram_ras_n     => sdram_ras_n_o,
         sdram_cas_n     => sdram_cas_n_o,
         sdram_we_n      => sdram_we_n_o,
         sdram_cs_n      => sdram_cs_n_o,
         sdram_ba        => sdram_ba_o,
         sdram_a         => sdram_a_o,
         sdram_dqml      => sdram_dqml_o,
         sdram_dqmh      => sdram_dqmh_o,
         sdram_dq        => sdram_dq_io
      ); -- i_atarist

   -- both hard disks share one LBA (only one request is active at a time)
   sd_lba_o(95 downto 64)    <= hd_lba;
   sd_lba_o(127 downto 96)   <= hd_lba;
   sd_lba_o(63 downto 32)    <= sd_lba_o(31 downto 0);   -- floppy B: (fdc1772 has one LBA for both drives)
   sd_buff_din_o(31 downto 16) <= sd_buff_din_o(15 downto 0);
   sd_buff_din_o(47 downto 32) <= hd_buff_din;
   sd_buff_din_o(63 downto 48) <= hd_buff_din;

   -- The OSM overlay (analog pipeline) always runs at 32 MHz: In the color modes the M2M
   -- scandoubler doubles the 16 MHz pixel rate, in the monochrome mode the pixel rate is 32 MHz.
   video_ce_ovl_o <= '1';

   audio_left_o  <= signed(audio_l);
   audio_right_o <= signed(audio_r);

   i_keyboard : entity work.keyboard
      generic map (
         G_CLK_SPEED          => CORE_CLK_SPEED
      )
      port map (
         clk_main_i           => clk_main_i,

         -- Interface to the MEGA65 keyboard
         key_num_i            => kb_key_num_i,
         key_pressed_n_i      => kb_key_pressed_n_i,

         -- Atari ST keyboard matrix
         st_matrix_n_o        => st_matrix_n
      ); -- i_keyboard

end architecture synthesis;

