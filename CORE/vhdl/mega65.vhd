----------------------------------------------------------------------------------
-- Atari ST/STe for MEGA65
--
-- MEGA65 main file that contains the whole machine
--
-- MiSTer2MEGA65 done by sy2002 and MJoergen in 2022 and licensed under GPL v3
-- Atari ST port 2026, licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.globals.all;
use work.types_pkg.all;
use work.video_modes_pkg.all;
use work.vdrives_pkg.all;

library xpm;
use xpm.vcomponents.all;

library unisim;                                 -- JTAG probe of the joystick ports (BSCANE2)
use unisim.vcomponents.all;

entity MEGA65_Core is
generic (
   G_BOARD : string                                         -- Which platform are we running on.
);
port (
   --------------------------------------------------------------------------------------------------------
   -- QNICE Clock Domain
   --------------------------------------------------------------------------------------------------------

   -- Get QNICE clock from the framework: for the vdrives as well as for RAMs and ROMs
   qnice_clk_i             : in  std_logic;
   qnice_rst_i             : in  std_logic;

   -- Video and audio mode control
   qnice_dvi_o             : out std_logic;              -- 0=HDMI (with sound), 1=DVI (no sound)
   qnice_video_mode_o      : out video_mode_type;        -- Defined in video_modes_pkg.vhd
   qnice_osm_cfg_scaling_o : out std_logic_vector(8 downto 0);
   qnice_scandoubler_o     : out std_logic;              -- 0 = no scandoubler, 1 = scandoubler
   qnice_scanlines_o       : out std_logic_vector(1 downto 0);   -- VGA scanlines: 0 = off, 1..3 = 25/50/75%
   qnice_audio_mute_o      : out std_logic;
   qnice_audio_filter_o    : out std_logic;
   qnice_zoom_crop_o       : out std_logic;
   qnice_ascal_mode_o      : out std_logic_vector(1 downto 0);
   qnice_ascal_polyphase_o : out std_logic;
   qnice_ascal_triplebuf_o : out std_logic;
   qnice_retro15kHz_o      : out std_logic;              -- 0 = normal frequency, 1 = retro 15 kHz frequency
   qnice_csync_o           : out std_logic;              -- 0 = normal HS/VS, 1 = Composite Sync  

   -- Flip joystick ports
   qnice_flip_joyports_o   : out std_logic;

   -- On-Screen-Menu selections
   qnice_osm_control_i     : in  std_logic_vector(255 downto 0);

   -- QNICE general purpose register
   qnice_gp_reg_i          : in  std_logic_vector(255 downto 0);

   -- Core-specific devices
   qnice_dev_id_i          : in  std_logic_vector(15 downto 0);
   qnice_dev_addr_i        : in  std_logic_vector(27 downto 0);
   qnice_dev_data_i        : in  std_logic_vector(15 downto 0);
   qnice_dev_data_o        : out std_logic_vector(15 downto 0);
   qnice_dev_ce_i          : in  std_logic;
   qnice_dev_we_i          : in  std_logic;
   qnice_dev_wait_o        : out std_logic;

   --------------------------------------------------------------------------------------------------------
   -- HyperRAM Clock Domain
   --------------------------------------------------------------------------------------------------------

   hr_clk_i                : in  std_logic;
   hr_rst_i                : in  std_logic;
   hr_core_write_o         : out std_logic;
   hr_core_read_o          : out std_logic;
   hr_core_address_o       : out std_logic_vector(31 downto 0);
   hr_core_writedata_o     : out std_logic_vector(15 downto 0);
   hr_core_byteenable_o    : out std_logic_vector( 1 downto 0);
   hr_core_burstcount_o    : out std_logic_vector( 7 downto 0);
   hr_core_readdata_i      : in  std_logic_vector(15 downto 0);
   hr_core_readdatavalid_i : in  std_logic;
   hr_core_waitrequest_i   : in  std_logic;
   hr_high_i               : in  std_logic;  -- Core is too fast
   hr_low_i                : in  std_logic;  -- Core is too slow

   --------------------------------------------------------------------------------------------------------
   -- Video Clock Domain
   --------------------------------------------------------------------------------------------------------

   video_clk_o             : out std_logic;
   video_rst_o             : out std_logic;
   video_ce_o              : out std_logic;
   video_ce_ovl_o          : out std_logic;
   video_red_o             : out std_logic_vector(7 downto 0);
   video_green_o           : out std_logic_vector(7 downto 0);
   video_blue_o            : out std_logic_vector(7 downto 0);
   video_vs_o              : out std_logic;
   video_hs_o              : out std_logic;
   video_hblank_o          : out std_logic;
   video_vblank_o          : out std_logic;

   --------------------------------------------------------------------------------------------------------
   -- Core Clock Domain
   --------------------------------------------------------------------------------------------------------

   clk_i                   : in  std_logic;              -- 100 MHz clock

   -- Share clock and reset with the framework
   main_clk_o              : out std_logic;              -- CORE's 32.083 MHz clock
   main_rst_o              : out std_logic;              -- CORE's reset, synchronized

   -- M2M's reset manager provides 2 signals:
   --    m2m:   Reset the whole machine: Core and Framework
   --    core:  Only reset the core
   main_reset_m2m_i        : in  std_logic;
   main_reset_core_i       : in  std_logic;

   main_pause_core_i       : in  std_logic;

   -- On-Screen-Menu selections
   main_osm_control_i      : in  std_logic_vector(255 downto 0);

   -- QNICE general purpose register converted to main clock domain
   main_qnice_gp_reg_i     : in  std_logic_vector(255 downto 0);

   -- Audio output (Signed PCM)
   main_audio_left_o       : out signed(15 downto 0);
   main_audio_right_o      : out signed(15 downto 0);

   -- M2M Keyboard interface (incl. power led and drive led)
   main_kb_key_num_i       : in  integer range 0 to 79;  -- cycles through all MEGA65 keys
   main_kb_key_pressed_n_i : in  std_logic;              -- low active: debounced feedback: is kb_key_num_i pressed right now?
   main_power_led_o        : out std_logic;
   main_power_led_col_o    : out std_logic_vector(23 downto 0);
   main_drive_led_o        : out std_logic;
   main_drive_led_col_o    : out std_logic_vector(23 downto 0);

   -- Joysticks and paddles input
   main_joy_1_up_n_i       : in  std_logic;
   main_joy_1_down_n_i     : in  std_logic;
   main_joy_1_left_n_i     : in  std_logic;
   main_joy_1_right_n_i    : in  std_logic;
   main_joy_1_fire_n_i     : in  std_logic;
   main_joy_1_up_n_o       : out std_logic;
   main_joy_1_down_n_o     : out std_logic;
   main_joy_1_left_n_o     : out std_logic;
   main_joy_1_right_n_o    : out std_logic;
   main_joy_1_fire_n_o     : out std_logic;
   main_joy_2_up_n_i       : in  std_logic;
   main_joy_2_down_n_i     : in  std_logic;
   main_joy_2_left_n_i     : in  std_logic;
   main_joy_2_right_n_i    : in  std_logic;
   main_joy_2_fire_n_i     : in  std_logic;
   main_joy_2_up_n_o       : out std_logic;
   main_joy_2_down_n_o     : out std_logic;
   main_joy_2_left_n_o     : out std_logic;
   main_joy_2_right_n_o    : out std_logic;
   main_joy_2_fire_n_o     : out std_logic;

   main_pot1_x_i           : in  std_logic_vector(7 downto 0);
   main_pot1_y_i           : in  std_logic_vector(7 downto 0);
   main_pot2_x_i           : in  std_logic_vector(7 downto 0);
   main_pot2_y_i           : in  std_logic_vector(7 downto 0);
   main_rtc_i              : in  std_logic_vector(64 downto 0);

   -- CBM-488/IEC serial port
   iec_reset_n_o           : out std_logic;
   iec_atn_n_o             : out std_logic;
   iec_clk_en_o            : out std_logic;
   iec_clk_n_i             : in  std_logic;
   iec_clk_n_o             : out std_logic;
   iec_data_en_o           : out std_logic;
   iec_data_n_i            : in  std_logic;
   iec_data_n_o            : out std_logic;
   iec_srq_en_o            : out std_logic;
   iec_srq_n_i             : in  std_logic;
   iec_srq_n_o             : out std_logic;

   -- C64 Expansion Port (aka Cartridge Port)
   cart_en_o               : out std_logic;  -- Enable port, active high
   cart_phi2_o             : out std_logic;
   cart_dotclock_o         : out std_logic;
   cart_dma_i              : in  std_logic;
   cart_reset_oe_o         : out std_logic;
   cart_reset_i            : in  std_logic;
   cart_reset_o            : out std_logic;
   cart_game_oe_o          : out std_logic;
   cart_game_i             : in  std_logic;
   cart_game_o             : out std_logic;
   cart_exrom_oe_o         : out std_logic;
   cart_exrom_i            : in  std_logic;
   cart_exrom_o            : out std_logic;
   cart_nmi_oe_o           : out std_logic;
   cart_nmi_i              : in  std_logic;
   cart_nmi_o              : out std_logic;
   cart_irq_oe_o           : out std_logic;
   cart_irq_i              : in  std_logic;
   cart_irq_o              : out std_logic;
   cart_roml_oe_o          : out std_logic;
   cart_roml_i             : in  std_logic;
   cart_roml_o             : out std_logic;
   cart_romh_oe_o          : out std_logic;
   cart_romh_i             : in  std_logic;
   cart_romh_o             : out std_logic;
   cart_ctrl_oe_o          : out std_logic; -- 0 : tristate (i.e. input), 1 : output
   cart_ba_i               : in  std_logic;
   cart_rw_i               : in  std_logic;
   cart_io1_i              : in  std_logic;
   cart_io2_i              : in  std_logic;
   cart_ba_o               : out std_logic;
   cart_rw_o               : out std_logic;
   cart_io1_o              : out std_logic;
   cart_io2_o              : out std_logic;
   cart_addr_oe_o          : out std_logic; -- 0 : tristate (i.e. input), 1 : output
   cart_a_i                : in  unsigned(15 downto 0);
   cart_a_o                : out unsigned(15 downto 0);
   cart_data_oe_o          : out std_logic; -- 0 : tristate (i.e. input), 1 : output
   cart_d_i                : in  unsigned( 7 downto 0);
   cart_d_o                : out unsigned( 7 downto 0);

   -- SDRAM (MEGA65 R4/R5/R6): 32M x 16 bit, IS42S16320F
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
   sdram_dq_io             : inout std_logic_vector(15 downto 0);

   -- PMOD headers: serial port, MIDI and parallel port (see main.vhd)
   p1lo_io                 : inout std_logic_vector(3 downto 0);
   p1hi_io                 : inout std_logic_vector(3 downto 0);
   p2lo_io                 : inout std_logic_vector(3 downto 0);
   p2hi_io                 : inout std_logic_vector(3 downto 0);
   pmod1_en_o              : out   std_logic;
   pmod2_en_o              : out   std_logic
);
end entity MEGA65_Core;

architecture synthesis of MEGA65_Core is

-- JTAG probe of the joystick ports (USER2 data register, 96 bits, see below)
type jp_cnt_t is array (0 to 4) of unsigned(7 downto 0);
signal jp_cnt       : jp_cnt_t := (others => (others => '0'));
signal jp_old       : std_logic_vector(4 downto 0) := (others => '1');
signal jp_free      : unsigned(23 downto 0) := (others => '0');
signal jp_snap      : std_logic_vector(95 downto 0);
signal jp_sr        : std_logic_vector(95 downto 0);
signal jp_capture, jp_sel, jp_shift, jp_tck, jp_tdi : std_logic;

-- JTAG probe of the keyboard (USER3 data register, 176 bits, see below)
signal kp_keys      : std_logic_vector(79 downto 0) := (others => '1');
signal kp_cnt_a     : unsigned(7 downto 0) := (others => '0');
signal kp_cnt_s     : unsigned(7 downto 0) := (others => '0');
signal kp_cnt_st_a  : unsigned(7 downto 0) := (others => '0');
signal kp_st_a_old  : std_logic := '1';
signal kp_st_matrix : std_logic_vector(119 downto 0);
signal kp_kbd_bytes : std_logic_vector(31 downto 0);
signal kp_snap      : std_logic_vector(175 downto 0);
signal kp_sr        : std_logic_vector(175 downto 0);
signal kp_capture, kp_sel, kp_shift, kp_tck, kp_tdi : std_logic;

---------------------------------------------------------------------------------------------
-- Clocks and active high reset signals for each clock domain
---------------------------------------------------------------------------------------------

signal main_clk               : std_logic;               -- Core main clock (32.083 MHz)
signal main_rst               : std_logic;
signal sdram_clk              : std_logic;               -- SDRAM clock (96.25 MHz)
signal ikbd_clk               : std_logic;               -- IKBD clock (2.005 MHz)

---------------------------------------------------------------------------------------------
-- On-Screen-Menu (OSM) items: must match the positions of the items in config.vhd
---------------------------------------------------------------------------------------------

constant C_MENU_ST             : natural := 12;
constant C_MENU_STE            : natural := 13;
constant C_MENU_MSTE           : natural := 14;
constant C_MENU_STEROIDS       : natural := 15;
constant C_MENU_MEM_512K       : natural := 21;
constant C_MENU_MEM_1M         : natural := 22;
constant C_MENU_MEM_2M         : natural := 23;
constant C_MENU_MEM_4M         : natural := 24;
constant C_MENU_MEM_8M         : natural := 25;
constant C_MENU_MEM_14M        : natural := 26;
constant C_MENU_BLITTER        : natural := 32;
constant C_MENU_MONO           : natural := 33;
constant C_MENU_MONO60         : natural := 34;
constant C_MENU_BORDER         : natural := 35;
constant C_MENU_VIKING         : natural := 36;
constant C_MENU_STEREO         : natural := 37;
constant C_MENU_WPROT          : natural := 38;
constant C_MENU_FDSWAP         : natural := 39;
constant C_MENU_AMIGAMOUSE     : natural := 47;   -- mouse type: 46 Atari (default), 47 Amiga, 48 1351
constant C_MENU_MOUSE1351      : natural := 48;
constant C_MENU_JOYSWAP        : natural := 52;   -- mouse port: 51 port 1 (default), 52 port 2
constant C_MENU_STEPADS        : natural := 54;
constant C_MENU_PMOD           : natural := 55;
constant C_MENU_CUBASE         : natural := 56;
constant C_MENU_HDMI_16_9_50   : natural := 62;
constant C_MENU_HDMI_16_9_60   : natural := 63;
constant C_MENU_HDMI_4_3_50    : natural := 64;
constant C_MENU_HDMI_5_4_50    : natural := 65;
constant C_MENU_HDMI_640_60    : natural := 66;
constant C_MENU_HDMI_720_5994  : natural := 67;
constant C_MENU_SVGA_800_60    : natural := 68;
constant C_MENU_HDMI_DVI       : natural := 70;
constant C_MENU_VGA_15KHZ      : natural := 77;
constant C_MENU_VGA_CSYNC      : natural := 78;
constant C_MENU_SCANLINES_25   : natural := 81;
constant C_MENU_SCANLINES_50   : natural := 82;
constant C_MENU_SCANLINES_75   : natural := 83;
constant C_MENU_CRT_EMULATION  : natural := 86;
constant C_MENU_HDMI_ZOOM      : natural := 87;
constant C_MENU_IMPROVE_AUDIO  : natural := 88;
-- 82 "Reset Atari ST" is handled by the firmware (OSM_SEL_POST in m2m-rom.asm)

---------------------------------------------------------------------------------------------
-- main_clk (MiSTer core's clock)
---------------------------------------------------------------------------------------------

signal main_st_mem            : std_logic_vector(2 downto 0);
signal main_st_ste            : std_logic;
signal main_st_mste           : std_logic;

signal main_dio_addr          : std_logic_vector(23 downto 1);
signal main_dio_data          : std_logic_vector(15 downto 0);
signal main_dio_strobe        : std_logic;
signal main_dio_strobe_ack    : std_logic;
signal main_tos192k           : std_logic;
signal main_cart_loaded       : std_logic;
signal main_cart_loading      : std_logic;
signal main_tos_loading       : std_logic;
signal qnice_vga_15khz        : std_logic;   -- VGA: 15 kHz RGB instead of 31 kHz

signal main_img_mounted       : std_logic_vector(C_VDNUM - 1 downto 0);
signal main_img_readonly      : std_logic;
signal main_img_size          : std_logic_vector(31 downto 0);
signal main_sd_lba            : std_logic_vector(32 * C_VDNUM - 1 downto 0);
signal main_sd_rd             : std_logic_vector(C_VDNUM - 1 downto 0);
signal main_sd_wr             : std_logic_vector(C_VDNUM - 1 downto 0);
signal main_sd_ack            : std_logic_vector(C_VDNUM - 1 downto 0);
signal main_sd_buff_addr      : std_logic_vector(7 downto 0);
signal main_sd_buff_dout      : std_logic_vector(15 downto 0);
signal main_sd_buff_din       : std_logic_vector(16 * C_VDNUM - 1 downto 0);
signal main_sd_buff_wr        : std_logic;
signal main_floppy_led        : std_logic;
signal main_hd_led            : std_logic;
signal main_cache_dirty       : std_logic_vector(C_VDNUM - 1 downto 0);
signal main_video_31khz       : std_logic;

-- PMOD
signal main_pmod_in           : std_logic_vector(15 downto 0);
signal main_pmod_out          : std_logic_vector(15 downto 0);
signal main_pmod_oe           : std_logic_vector(15 downto 0);
signal pmod_pins              : std_logic_vector(15 downto 0);

---------------------------------------------------------------------------------------------
-- qnice_clk
---------------------------------------------------------------------------------------------

signal qnice_video_31khz      : std_logic;

-- TOS and cartridge loader
signal qnice_tos_ce           : std_logic;
signal qnice_cart_ce          : std_logic;
signal qnice_tosm_ce          : std_logic;
signal qnice_tos_we           : std_logic;
signal qnice_tos_wait         : std_logic;
signal qnice_csr_data         : std_logic_vector(15 downto 0);

-- Virtual drives
signal qnice_vd_data_o        : std_logic_vector(15 downto 0);
signal qnice_vd_ce            : std_logic;
signal qnice_vd_we            : std_logic;
signal qnice_vd_wait          : std_logic;
signal qnice_vd_wait_cnt      : natural range 0 to 31;
signal main_vd_reset          : std_logic;
signal qnice_sd_lba           : vd_vec_array(C_VDNUM - 1 downto 0)(31 downto 0);
signal qnice_sd_rd            : vd_std_array(C_VDNUM - 1 downto 0);
signal qnice_sd_wr            : vd_std_array(C_VDNUM - 1 downto 0);
signal qnice_sd_ack           : vd_std_array(C_VDNUM - 1 downto 0);
signal qnice_sd_buff_addr     : std_logic_vector(13 downto 0);
signal qnice_sd_buff_dout     : std_logic_vector(7 downto 0);
signal qnice_sd_buff_din      : vd_vec_array(C_VDNUM - 1 downto 0)(7 downto 0);
signal qnice_sd_buff_wr       : std_logic;
signal qnice_sd_buff_wr_acc   : std_logic;

-- QNICE needs to wait this amount of QNICE clock cycles when reading a byte from the
-- FDC's sector buffer (see fdc_bridge.vhd)
constant C_VD_DIN_WAIT        : natural := 24;

-- Disk image buffers in HyperRAM (word addresses)
constant C_VD0_BASE           : unsigned(31 downto 0) := shift_left(resize(unsigned(C_HMAP_VD0), 32), 12);
constant C_VD1_BASE           : unsigned(31 downto 0) := shift_left(resize(unsigned(C_HMAP_VD1), 32), 12);
signal qnice_buf_cs           : std_logic;
signal qnice_buf_address      : std_logic_vector(31 downto 0);
signal qnice_buf_writedata    : std_logic_vector(15 downto 0);
signal qnice_buf_byteenable   : std_logic_vector(1 downto 0);
signal qnice_buf_readdata     : std_logic_vector(15 downto 0);
signal qnice_buf_wait         : std_logic;

signal qnice_avm_write        : std_logic;
signal qnice_avm_read         : std_logic;
signal qnice_avm_address      : std_logic_vector(31 downto 0);
signal qnice_avm_writedata    : std_logic_vector(15 downto 0);
signal qnice_avm_byteenable   : std_logic_vector(1 downto 0);
signal qnice_avm_burstcount   : std_logic_vector(7 downto 0);
signal qnice_avm_readdata     : std_logic_vector(15 downto 0);
signal qnice_avm_readdatavalid: std_logic;
signal qnice_avm_waitrequest  : std_logic;

begin

   -- Tristate all expansion port drivers that we can directly control
   -- @TODO: As soon as we support modules that can act as busmaster, we need to become more flexible here
   cart_ctrl_oe_o       <= '0';
   cart_addr_oe_o       <= '0';
   cart_data_oe_o       <= '0';

   -- Due to a bug in the R5/R6 boards, the cartridge port needs to be enabled for joystick port 2 to work
   cart_en_o            <= '1';

   cart_reset_oe_o      <= '0';
   cart_game_oe_o       <= '0';
   cart_exrom_oe_o      <= '0';
   cart_nmi_oe_o        <= '0';
   cart_irq_oe_o        <= '0';
   cart_roml_oe_o       <= '0';
   cart_romh_oe_o       <= '0';

   -- Default values for all signals
   cart_phi2_o          <= '0';
   cart_reset_o         <= '1';
   cart_dotclock_o      <= '0';
   cart_game_o          <= '1';
   cart_exrom_o         <= '1';
   cart_nmi_o           <= '1';
   cart_irq_o           <= '1';
   cart_roml_o          <= '0';
   cart_romh_o          <= '0';
   cart_ba_o            <= '0';
   cart_rw_o            <= '0';
   cart_io1_o           <= '0';
   cart_io2_o           <= '0';
   cart_a_o             <= (others => '0');
   cart_d_o             <= (others => '0');

   main_joy_1_up_n_o    <= '1';
   main_joy_1_down_n_o  <= '1';
   main_joy_1_left_n_o  <= '1';
   main_joy_1_right_n_o <= '1';
   main_joy_1_fire_n_o  <= '1';
   main_joy_2_up_n_o    <= '1';
   main_joy_2_down_n_o  <= '1';
   main_joy_2_left_n_o  <= '1';
   main_joy_2_right_n_o <= '1';
   main_joy_2_fire_n_o  <= '1';

   -- CBM-488/IEC serial port: not used
   iec_reset_n_o        <= '1';
   iec_atn_n_o          <= '1';
   iec_clk_en_o         <= '0';
   iec_clk_n_o          <= '1';
   iec_data_en_o        <= '0';
   iec_data_n_o         <= '1';
   iec_srq_en_o         <= '0';
   iec_srq_n_o          <= '1';

   -- MMCME2_ADV clock generators:
   --   Atari ST: 32.083 MHz (system), 96.25 MHz (SDRAM), 2.005 MHz (IKBD)
   clk_gen : entity work.clk
      port map (
         sys_clk_i         => clk_i,           -- expects 100 MHz
         main_clk_o        => main_clk,        -- CORE's 32.083 MHz clock
         main_rst_o        => main_rst,        -- CORE's reset, synchronized
         sdram_clk_o       => sdram_clk,
         ikbd_clk_o        => ikbd_clk
      ); -- clk_gen

   main_clk_o  <= main_clk;
   main_rst_o  <= main_rst;
   video_clk_o <= main_clk;
   video_rst_o <= main_rst;

   ---------------------------------------------------------------------------------------------
   -- main_clk (MiSTer core's clock)
   ---------------------------------------------------------------------------------------------

   -- MEGA65's power led: By default, it is on and glows green when the MEGA65 is powered on.
   -- We switch it to blue when a long reset is detected and as long as the user keeps pressing the preset button
   main_power_led_o     <= '1';
   main_power_led_col_o <= x"0000FF" when main_reset_m2m_i else x"00FF00";

   -- Drive led: green while the ST accesses a floppy drive, red for the hard disks,
   -- yellow while the write cache of a floppy is dirty
   main_drive_led_o     <= main_floppy_led or main_hd_led or (or main_cache_dirty);
   main_drive_led_col_o <= x"FFFF00" when (or main_cache_dirty) = '1' else
                           x"FF0000" when main_hd_led = '1' else
                           x"00FF00";

   -- Machine type
   main_st_ste  <= main_osm_control_i(C_MENU_STE) or main_osm_control_i(C_MENU_STEROIDS);
   main_st_mste <= main_osm_control_i(C_MENU_MSTE) or main_osm_control_i(C_MENU_STEROIDS);

   -- Memory size
   main_st_mem  <= "000" when main_osm_control_i(C_MENU_MEM_512K) = '1' else
                   "010" when main_osm_control_i(C_MENU_MEM_2M)   = '1' else
                   "011" when main_osm_control_i(C_MENU_MEM_4M)   = '1' else
                   "100" when main_osm_control_i(C_MENU_MEM_8M)   = '1' else
                   "101" when main_osm_control_i(C_MENU_MEM_14M)  = '1' else
                   "001";   -- 1 MB

   -- main.vhd contains the actual MiSTer core
   i_main : entity work.main
      generic map (
         G_VDNUM              => C_VDNUM
      )
      port map (
         clk_main_i           => main_clk,
         clk_sdram_i          => sdram_clk,
         clk_ikbd_i           => ikbd_clk,
         reset_soft_i         => main_reset_core_i,
         reset_hard_i         => main_reset_m2m_i,
         pause_i              => main_pause_core_i,
         init_i               => main_rst,

         clk_main_speed_i     => CORE_CLK_SPEED,

         -- Atari ST configuration
         st_mem_i             => main_st_mem,
         st_ste_i             => main_st_ste,
         st_mste_i            => main_st_mste,
         st_blitter_i         => main_osm_control_i(C_MENU_BLITTER),
         st_mono_i            => main_osm_control_i(C_MENU_MONO),
         st_mono60_i          => main_osm_control_i(C_MENU_MONO60),
         st_full_border_i     => main_osm_control_i(C_MENU_BORDER),
         st_psg_stereo_i      => main_osm_control_i(C_MENU_STEREO),
         st_fdc_wp_i          => (others => main_osm_control_i(C_MENU_WPROT)),
         st_fd_swap_i         => main_osm_control_i(C_MENU_FDSWAP),
         st_crop_i            => main_osm_control_i(C_MENU_HDMI_ZOOM),
         st_joy_swap_i        => main_osm_control_i(C_MENU_JOYSWAP),
         st_viking_i          => main_osm_control_i(C_MENU_VIKING),
         st_ste_pads_i        => main_osm_control_i(C_MENU_STEPADS),
         st_mouse1351_i       => main_osm_control_i(C_MENU_MOUSE1351),
         st_amigamouse_i      => main_osm_control_i(C_MENU_AMIGAMOUSE),
         st_pmod_i            => main_osm_control_i(C_MENU_PMOD),
         st_cubase_i          => main_osm_control_i(C_MENU_CUBASE),
         rtc_i                => main_rtc_i,

         -- TOS loader
         dio_addr_i           => main_dio_addr,
         dio_data_i           => main_dio_data,
         dio_strobe_i         => main_dio_strobe,
         dio_strobe_ack_o     => main_dio_strobe_ack,
         tos192k_i            => main_tos192k,
         cart_loaded_i        => main_cart_loaded,
         cart_loading_i       => main_cart_loading,
         tos_loading_i        => main_tos_loading,

         -- Floppy drives
         img_mounted_i        => main_img_mounted,
         img_readonly_i       => main_img_readonly,
         img_size_i           => main_img_size,
         sd_lba_o             => main_sd_lba,
         sd_rd_o              => main_sd_rd,
         sd_wr_o              => main_sd_wr,
         sd_ack_i             => main_sd_ack,
         sd_buff_addr_i       => main_sd_buff_addr,
         sd_buff_dout_i       => main_sd_buff_dout,
         sd_buff_din_o        => main_sd_buff_din,
         sd_buff_wr_i         => main_sd_buff_wr,
         floppy_led_o         => main_floppy_led,
         hd_led_o             => main_hd_led,

         -- Video output
         video_ce_o           => video_ce_o,
         video_ce_ovl_o       => video_ce_ovl_o,
         video_red_o          => video_red_o,
         video_green_o        => video_green_o,
         video_blue_o         => video_blue_o,
         video_vs_o           => video_vs_o,
         video_hs_o           => video_hs_o,
         video_hblank_o       => video_hblank_o,
         video_vblank_o       => video_vblank_o,
         video_31khz_o        => main_video_31khz,

         -- audio output (pcm format, signed values)
         audio_left_o         => main_audio_left_o,
         audio_right_o        => main_audio_right_o,

         -- M2M Keyboard interface
         kb_key_num_i         => main_kb_key_num_i,
         kb_key_pressed_n_i   => main_kb_key_pressed_n_i,

         -- MEGA65 joysticks and paddles/mouse/potentiometers
         joy_1_up_n_i         => main_joy_1_up_n_i,
         joy_1_down_n_i       => main_joy_1_down_n_i,
         joy_1_left_n_i       => main_joy_1_left_n_i,
         joy_1_right_n_i      => main_joy_1_right_n_i,
         joy_1_fire_n_i       => main_joy_1_fire_n_i,

         joy_2_up_n_i         => main_joy_2_up_n_i,
         joy_2_down_n_i       => main_joy_2_down_n_i,
         joy_2_left_n_i       => main_joy_2_left_n_i,
         joy_2_right_n_i      => main_joy_2_right_n_i,
         joy_2_fire_n_i       => main_joy_2_fire_n_i,

         pot1_x_i             => main_pot1_x_i,
         pot1_y_i             => main_pot1_y_i,
         pot2_x_i             => main_pot2_x_i,
         pot2_y_i             => main_pot2_y_i,

         -- PMOD
         pmod_in_i            => main_pmod_in,
         pmod_out_o           => main_pmod_out,
         pmod_oe_o            => main_pmod_oe,

         -- SDRAM
         sdram_clk_o          => sdram_clk_o,
         sdram_cke_o          => sdram_cke_o,
         sdram_ras_n_o        => sdram_ras_n_o,
         sdram_cas_n_o        => sdram_cas_n_o,
         sdram_we_n_o         => sdram_we_n_o,
         sdram_cs_n_o         => sdram_cs_n_o,
         sdram_ba_o           => sdram_ba_o,
         sdram_a_o            => sdram_a_o,
         sdram_dqml_o         => sdram_dqml_o,
         sdram_dqmh_o         => sdram_dqmh_o,
         sdram_dq_io          => sdram_dq_io,
         dbg_st_matrix_o      => kp_st_matrix,
         dbg_kbd_bytes_o      => kp_kbd_bytes
      ); -- i_main

   ---------------------------------------------------------------------------------------------
   -- Audio and video settings (QNICE clock domain)
   ---------------------------------------------------------------------------------------------

   -- Due to a discussion on the MEGA65 discord (https://discord.com/channels/719326990221574164/794775503818588200/1039457688020586507)
   -- we decided to choose a naming convention for the PAL modes that might be more intuitive for the end users than it is
   -- for the programmers: "4:3" means "meant to be run on a 4:3 monitor", "5:4 on a 5:4 monitor".
   qnice_video_mode_o <= C_VIDEO_SVGA_800_60   when qnice_osm_control_i(C_MENU_SVGA_800_60)    = '1' else
                         C_VIDEO_HDMI_720_5994 when qnice_osm_control_i(C_MENU_HDMI_720_5994)  = '1' else
                         C_VIDEO_HDMI_640_60   when qnice_osm_control_i(C_MENU_HDMI_640_60)    = '1' else
                         C_VIDEO_HDMI_5_4_50   when qnice_osm_control_i(C_MENU_HDMI_5_4_50)    = '1' else
                         C_VIDEO_HDMI_4_3_50   when qnice_osm_control_i(C_MENU_HDMI_4_3_50)    = '1' else
                         C_VIDEO_HDMI_16_9_60  when qnice_osm_control_i(C_MENU_HDMI_16_9_60)   = '1' else
                         C_VIDEO_HDMI_16_9_50;

   -- The ST's color modes are 15 kHz modes and need the scandoubler for VGA, while the
   -- monochrome mode (71 Hz) and the (downscaled) Viking mode are already 31 kHz modes.
   i_cdc_mono : xpm_cdc_single
      generic map (
         DEST_SYNC_FF   => 2,
         INIT_SYNC_FF   => 0,
         SIM_ASSERT_CHK => 0,
         SRC_INPUT_REG  => 1
      )
      port map (
         src_clk  => main_clk,
         src_in   => main_video_31khz,
         dest_clk => qnice_clk_i,
         dest_out => qnice_video_31khz
      ); -- i_cdc_mono

   -- Use On-Screen-Menu selections to configure several audio and video settings
   -- Video and audio mode control
   qnice_dvi_o                <= qnice_osm_control_i(C_MENU_HDMI_DVI);         -- 0=HDMI (with sound), 1=DVI (no sound)
   qnice_vga_15khz            <= qnice_osm_control_i(C_MENU_VGA_15KHZ) or qnice_osm_control_i(C_MENU_VGA_CSYNC);

   -- VGA: 31 kHz (scandoubler for the 15 kHz color modes) or 15 kHz (RGB for CRTs and SCART)
   qnice_scandoubler_o        <= not qnice_video_31khz and not qnice_vga_15khz;
   qnice_scanlines_o          <= "01" when qnice_osm_control_i(C_MENU_SCANLINES_25) = '1' else
                                 "10" when qnice_osm_control_i(C_MENU_SCANLINES_50) = '1' else
                                 "11" when qnice_osm_control_i(C_MENU_SCANLINES_75) = '1' else
                                 "00";
   qnice_audio_mute_o         <= '0';                                         -- audio is not muted
   qnice_audio_filter_o       <= qnice_osm_control_i(C_MENU_IMPROVE_AUDIO);   -- 0 = raw audio, 1 = use filters from globals.vhd
   qnice_zoom_crop_o          <= qnice_osm_control_i(C_MENU_HDMI_ZOOM);       -- 0 = no zoom/crop (the core crops the border)

   -- These two signals are often used as a pair (i.e. both '1'), particularly when
   -- you want to run old analog cathode ray tube monitors or TVs (via SCART)
   -- If you want to provide your users a choice, then a good choice is:
   --    "Standard VGA":                     qnice_retro15kHz_o=0 and qnice_csync_o=0
   --    "Retro 15 kHz with HSync and VSync" qnice_retro15kHz_o=1 and qnice_csync_o=0
   --    "Retro 15 kHz with CSync"           qnice_retro15kHz_o=1 and qnice_csync_o=1
   qnice_retro15kHz_o         <= qnice_vga_15khz;
   qnice_csync_o              <= qnice_osm_control_i(C_MENU_VGA_CSYNC);
   qnice_osm_cfg_scaling_o    <= (others => '1');

   -- ascal filters that are applied while processing the input
   -- 00 : Nearest Neighbour
   -- 01 : Bilinear
   -- 10 : Sharp Bilinear
   -- 11 : Bicubic
   qnice_ascal_mode_o         <= "00";

   -- If polyphase is '1' then the ascal filter mode is ignored and polyphase filters are used instead
   -- @TODO: Right now, the filters are hardcoded in the M2M framework, we need to make them changeable inside m2m-rom.asm
   qnice_ascal_polyphase_o    <= qnice_osm_control_i(C_MENU_CRT_EMULATION);

   -- ascal triple-buffering
   -- @TODO: Right now, the M2M framework only supports OFF, so do not touch until the framework is upgraded
   qnice_ascal_triplebuf_o    <= '0';

   -- Joystick ports are swapped via the Atari ST's own menu item (see main.vhd)
   qnice_flip_joyports_o      <= '0';

   ---------------------------------------------------------------------------------------------
   -- Core specific device handling (QNICE clock domain)
   ---------------------------------------------------------------------------------------------

   core_specific_devices : process(all)
   begin
      -- make sure that this is x"EEEE" by default and avoid a register here by having this default value
      qnice_dev_data_o     <= x"EEEE";
      qnice_dev_wait_o     <= '0';

      qnice_tos_ce         <= '0';
      qnice_cart_ce        <= '0';
      qnice_tosm_ce        <= '0';
      qnice_tos_we         <= '0';
      qnice_vd_ce          <= '0';
      qnice_vd_we          <= '0';
      qnice_buf_cs         <= '0';

      case qnice_dev_id_i is

         -- TOS loader (write only)
         when C_DEV_ST_TOS =>
            qnice_tos_ce         <= qnice_dev_ce_i;
            qnice_tos_we         <= qnice_dev_we_i;
            qnice_dev_wait_o     <= qnice_tos_wait;

         -- Cartridge loader
         when C_DEV_ST_CART =>
            qnice_cart_ce        <= qnice_dev_ce_i;
            qnice_tos_we         <= qnice_dev_we_i;
            qnice_dev_data_o     <= qnice_csr_data;
            qnice_dev_wait_o     <= qnice_tos_wait;

         -- TOS loader: TOS image chosen in the menu
         when C_DEV_ST_TOSMAN =>
            qnice_tosm_ce        <= qnice_dev_ce_i;
            qnice_tos_we         <= qnice_dev_we_i;
            qnice_dev_data_o     <= qnice_csr_data;
            qnice_dev_wait_o     <= qnice_tos_wait;

         -- Virtual drives
         when C_DEV_ST_VD =>
            qnice_vd_ce          <= qnice_dev_ce_i;
            qnice_vd_we          <= qnice_dev_we_i;
            qnice_dev_data_o     <= qnice_vd_data_o;
            qnice_dev_wait_o     <= qnice_vd_wait;

         -- Disk image buffers in HyperRAM
         when C_DEV_ST_VD0_BUF | C_DEV_ST_VD1_BUF =>
            qnice_buf_cs         <= qnice_dev_ce_i;
            qnice_dev_wait_o     <= qnice_buf_wait;
            if qnice_dev_addr_i(0) = '0' then
               qnice_dev_data_o  <= x"00" & qnice_buf_readdata(7 downto 0);
            else
               qnice_dev_data_o  <= x"00" & qnice_buf_readdata(15 downto 8);
            end if;

         when others => null;
      end case;
   end process core_specific_devices;

   ---------------------------------------------------------------------------------------
   -- TOS loader
   ---------------------------------------------------------------------------------------

   i_tos_loader : entity work.tos_loader
      port map (
         qnice_clk_i       => qnice_clk_i,
         qnice_rst_i       => qnice_rst_i,
         qnice_addr_i      => qnice_dev_addr_i,
         qnice_data_i      => qnice_dev_data_i,
         qnice_ce_i        => qnice_tos_ce,
         qnice_cart_ce_i   => qnice_cart_ce,
         qnice_tosm_ce_i   => qnice_tosm_ce,
         qnice_we_i        => qnice_tos_we,
         qnice_wait_o      => qnice_tos_wait,
         qnice_csr_data_o  => qnice_csr_data,

         main_clk_i        => main_clk,
         main_dio_addr_o   => main_dio_addr,
         main_dio_data_o   => main_dio_data,
         main_dio_strobe_o => main_dio_strobe,
         main_dio_ack_i    => main_dio_strobe_ack,
         main_tos192k_o    => main_tos192k,
         main_cart_loaded_o  => main_cart_loaded,
         main_cart_loading_o => main_cart_loading,
         main_tos_loading_o  => main_tos_loading
      ); -- i_tos_loader

   ---------------------------------------------------------------------------------------
   -- Disk image buffers: 2 MB per drive in HyperRAM
   --
   -- The firmware stores one byte per QNICE address. Two bytes are stored in one
   -- 16-bit HyperRAM word (even address = low byte).
   ---------------------------------------------------------------------------------------

   qnice_buf_address    <= std_logic_vector(C_VD0_BASE + resize(unsigned(qnice_dev_addr_i(20 downto 1)), 32))
                              when qnice_dev_id_i = C_DEV_ST_VD0_BUF else
                           std_logic_vector(C_VD1_BASE + resize(unsigned(qnice_dev_addr_i(20 downto 1)), 32));
   qnice_buf_writedata  <= qnice_dev_data_i(7 downto 0) & qnice_dev_data_i(7 downto 0);
   qnice_buf_byteenable <= "10" when qnice_dev_addr_i(0) = '1' else "01";

   i_qnice2hyperram : entity work.qnice2hyperram
      port map (
         clk_i                 => qnice_clk_i,
         rst_i                 => qnice_rst_i,
         s_qnice_wait_o        => qnice_buf_wait,
         s_qnice_address_i     => qnice_buf_address,
         s_qnice_cs_i          => qnice_buf_cs,
         s_qnice_write_i       => qnice_dev_we_i,
         s_qnice_writedata_i   => qnice_buf_writedata,
         s_qnice_byteenable_i  => qnice_buf_byteenable,
         s_qnice_readdata_o    => qnice_buf_readdata,
         m_avm_write_o         => qnice_avm_write,
         m_avm_read_o          => qnice_avm_read,
         m_avm_address_o       => qnice_avm_address,
         m_avm_writedata_o     => qnice_avm_writedata,
         m_avm_byteenable_o    => qnice_avm_byteenable,
         m_avm_burstcount_o    => qnice_avm_burstcount,
         m_avm_readdata_i      => qnice_avm_readdata,
         m_avm_readdatavalid_i => qnice_avm_readdatavalid,
         m_avm_waitrequest_i   => qnice_avm_waitrequest
      ); -- i_qnice2hyperram

   -- Clock domain crossing: QNICE to HyperRAM
   i_avm_fifo : entity work.avm_fifo
      generic map (
         G_WR_DEPTH     => 16,
         G_RD_DEPTH     => 16,
         G_FILL_SIZE    => 1,
         G_ADDRESS_SIZE => 32,
         G_DATA_SIZE    => 16
      )
      port map (
         s_clk_i               => qnice_clk_i,
         s_rst_i               => qnice_rst_i,
         s_avm_waitrequest_o   => qnice_avm_waitrequest,
         s_avm_write_i         => qnice_avm_write,
         s_avm_read_i          => qnice_avm_read,
         s_avm_address_i       => qnice_avm_address,
         s_avm_writedata_i     => qnice_avm_writedata,
         s_avm_byteenable_i    => qnice_avm_byteenable,
         s_avm_burstcount_i    => qnice_avm_burstcount,
         s_avm_readdata_o      => qnice_avm_readdata,
         s_avm_readdatavalid_o => qnice_avm_readdatavalid,
         m_clk_i               => hr_clk_i,
         m_rst_i               => hr_rst_i,
         m_avm_waitrequest_i   => hr_core_waitrequest_i,
         m_avm_write_o         => hr_core_write_o,
         m_avm_read_o          => hr_core_read_o,
         m_avm_address_o       => hr_core_address_o,
         m_avm_writedata_o     => hr_core_writedata_o,
         m_avm_byteenable_o    => hr_core_byteenable_o,
         m_avm_burstcount_o    => hr_core_burstcount_o,
         m_avm_readdata_i      => hr_core_readdata_i,
         m_avm_readdatavalid_i => hr_core_readdatavalid_i
      ); -- i_avm_fifo

   ---------------------------------------------------------------------------------------
   -- Virtual drive handler: floppy drives A: and B:
   ---------------------------------------------------------------------------------------

   -- Reading the byte from the FDC's sector buffer (window >= 1, register 0x000B) needs
   -- wait states because the data comes from the core clock domain (see fdc_bridge.vhd)
   vd_wait_proc : process(qnice_clk_i)
   begin
      if rising_edge(qnice_clk_i) then
         if qnice_vd_ce = '1' and qnice_dev_we_i = '0' and
            qnice_dev_addr_i(27 downto 12) /= x"0000" and qnice_dev_addr_i(11 downto 0) = x"00B" then
            if qnice_vd_wait_cnt /= C_VD_DIN_WAIT then
               qnice_vd_wait_cnt <= qnice_vd_wait_cnt + 1;
            end if;
         else
            qnice_vd_wait_cnt <= 0;
         end if;
      end if;
   end process vd_wait_proc;

   qnice_vd_wait <= '1' when qnice_vd_ce = '1' and qnice_dev_we_i = '0' and
                             qnice_dev_addr_i(27 downto 12) /= x"0000" and qnice_dev_addr_i(11 downto 0) = x"00B" and
                             qnice_vd_wait_cnt /= C_VD_DIN_WAIT
                    else '0';

   -- The virtual drives are only reset together with the framework (power-on, long press of
   -- the reset button), not by a reset of the Atari ST (menu item "Reset Atari ST", short press):
   -- like on MiSTer (and a real ST), the disks stay in their drives. The M2M firmware treats
   -- a reset of vdrives.vhd as "all drives unmounted", while the FDC and acsi_ctrl.sv would
   -- continue to use the images.
   i_cdc_vd_reset : xpm_cdc_sync_rst
      generic map (
         DEST_SYNC_FF   => 2,
         INIT           => 1,
         INIT_SYNC_FF   => 0,
         SIM_ASSERT_CHK => 0
      )
      port map (
         src_rst  => qnice_rst_i,
         dest_clk => main_clk,
         dest_rst => main_vd_reset
      ); -- i_cdc_vd_reset

   i_vdrives : entity work.vdrives
      generic map (
         VDNUM       => C_VDNUM
      )
      port map
      (
         clk_qnice_i       => qnice_clk_i,
         clk_core_i        => main_clk,
         reset_core_i      => main_vd_reset,

         -- Core clock domain
         img_mounted_o     => main_img_mounted,
         img_readonly_o    => main_img_readonly,
         img_size_o        => main_img_size,
         img_type_o        => open,
         drive_mounted_o   => open,

         -- Cache output signals: The dirty flags can be used to enforce data consistency
         -- (for example by ignoring/delaying a reset or delaying a drive unmount/mount, etc.)
         -- The flushing flags can be used to signal the fact that the caches are currently
         -- flushing to the user, for example using a special color/signal for example
         -- at the drive led
         cache_dirty_o     => main_cache_dirty,
         cache_flushing_o  => open,

         -- QNICE clock domain
         sd_lba_i          => qnice_sd_lba,
         sd_blk_cnt_i      => (others => (others => '0')),   -- always one block of 512 bytes
         sd_rd_i           => qnice_sd_rd,
         sd_wr_i           => qnice_sd_wr,
         sd_ack_o          => qnice_sd_ack,

         sd_buff_addr_o    => qnice_sd_buff_addr,
         sd_buff_dout_o    => qnice_sd_buff_dout,
         sd_buff_din_i     => qnice_sd_buff_din,
         sd_buff_wr_o      => qnice_sd_buff_wr,

         -- QNICE interface (MMIO, 4k-segmented)
         -- qnice_addr is 28-bit because we have a 16-bit window selector and a 4k window: 65536*4096 = 268.435.456 = 2^28
         qnice_addr_i      => qnice_dev_addr_i,
         qnice_data_i      => qnice_dev_data_i,
         qnice_data_o      => qnice_vd_data_o,
         qnice_ce_i        => qnice_vd_ce,
         qnice_we_i        => qnice_vd_we
      ); -- i_vdrives

   -- Write strobe for the sector buffers: every QNICE write access that writes '1' to the
   -- sd_buff_wr register (window 0, register 7): see fdc_bridge.vhd
   qnice_sd_buff_wr_acc <= '1' when qnice_vd_ce = '1' and qnice_dev_we_i = '1' and
                                    qnice_dev_addr_i(27 downto 12) = x"0000" and qnice_dev_addr_i(11 downto 0) = x"007" and
                                    qnice_dev_data_i(0) = '1'
                           else '0';

   i_fdc_bridge : entity work.fdc_bridge
      generic map (
         G_VDNUM           => C_VDNUM
      )
      port map (
         qnice_clk_i       => qnice_clk_i,
         qnice_rst_i       => qnice_rst_i,
         qnice_sd_lba_o    => qnice_sd_lba,
         qnice_sd_rd_o     => qnice_sd_rd,
         qnice_sd_wr_o     => qnice_sd_wr,
         qnice_sd_ack_i    => qnice_sd_ack,
         qnice_buff_addr_i => qnice_sd_buff_addr,
         qnice_buff_dout_i => qnice_sd_buff_dout,
         qnice_buff_din_o  => qnice_sd_buff_din,
         qnice_buff_wr_i   => qnice_sd_buff_wr_acc,

         main_clk_i        => main_clk,
         main_sd_lba_i     => main_sd_lba,
         main_sd_rd_i      => main_sd_rd,
         main_sd_wr_i      => main_sd_wr,
         main_sd_ack_o     => main_sd_ack,
         main_buff_addr_o  => main_sd_buff_addr,
         main_buff_dout_o  => main_sd_buff_dout,
         main_buff_din_i   => main_sd_buff_din,
         main_buff_wr_o    => main_sd_buff_wr
      ); -- i_fdc_bridge

   ---------------------------------------------------------------------------------------
   -- PMOD headers
   ---------------------------------------------------------------------------------------

   pmod_pins_gen : for i in 0 to 3 generate
      p1lo_io(i) <= main_pmod_out(i)      when main_pmod_oe(i)      = '1' else 'Z';
      p1hi_io(i) <= main_pmod_out(i + 4)  when main_pmod_oe(i + 4)  = '1' else 'Z';
      p2lo_io(i) <= main_pmod_out(i + 8)  when main_pmod_oe(i + 8)  = '1' else 'Z';
      p2hi_io(i) <= main_pmod_out(i + 12) when main_pmod_oe(i + 12) = '1' else 'Z';
   end generate pmod_pins_gen;

   pmod_pins <= p2hi_io & p2lo_io & p1hi_io & p1lo_io;

   -- PMOD power (3.3V load switches of the PMOD headers) only when the ST uses them
   pmod1_en_o <= main_osm_control_i(C_MENU_PMOD);
   pmod2_en_o <= main_osm_control_i(C_MENU_PMOD);

   i_cdc_pmod : xpm_cdc_array_single
      generic map (
         DEST_SYNC_FF   => 2,
         INIT_SYNC_FF   => 0,
         SIM_ASSERT_CHK => 0,
         SRC_INPUT_REG  => 0,
         WIDTH          => 16
      )
      port map (
         src_clk  => main_clk,
         src_in   => pmod_pins,
         dest_clk => main_clk,
         dest_out => main_pmod_in
      ); -- i_cdc_pmod

   -- JTAG probe of the joystick ports for debugging mice: JTAG instruction USER2 (0x03), then a 96 bit
   -- data register scan (LSB first) returns: 4..0: port 1 (fire, right, left, down, up; low active),
   -- 9..5: port 2, 12..10: menu Amiga mouse, 1351 mouse, swap ports, 23..16: pot 1 x, 31..24: pot 1 y,
   -- 71..32: edges of port 1 up, down, left, right, fire (8 bits each), 95..72: free running counter.
   jp_sample : process (main_clk)
      variable j1 : std_logic_vector(4 downto 0);
   begin
      if rising_edge(main_clk) then
         j1 := main_joy_1_fire_n_i & main_joy_1_right_n_i & main_joy_1_left_n_i & main_joy_1_down_n_i & main_joy_1_up_n_i;
         jp_old  <= j1;
         jp_free <= jp_free + 1;
         for i in 0 to 4 loop
            if j1(i) /= jp_old(i) then
               jp_cnt(i) <= jp_cnt(i) + 1;
            end if;
         end loop;
         jp_snap <= std_logic_vector(jp_free) &
                    std_logic_vector(jp_cnt(4)) & std_logic_vector(jp_cnt(3)) & std_logic_vector(jp_cnt(2)) &
                    std_logic_vector(jp_cnt(1)) & std_logic_vector(jp_cnt(0)) &
                    main_pot1_y_i & main_pot1_x_i & "000" &
                    main_osm_control_i(C_MENU_JOYSWAP) & main_osm_control_i(C_MENU_MOUSE1351) &
                    main_osm_control_i(C_MENU_AMIGAMOUSE) &
                    main_joy_2_fire_n_i & main_joy_2_right_n_i & main_joy_2_left_n_i & main_joy_2_down_n_i &
                    main_joy_2_up_n_i & j1;
      end if;
   end process jp_sample;

   jp_bscan : BSCANE2
      generic map (
         JTAG_CHAIN => 2
      )
      port map (
         CAPTURE => jp_capture,
         DRCK    => open,
         RESET   => open,
         RUNTEST => open,
         SEL     => jp_sel,
         SHIFT   => jp_shift,
         TCK     => jp_tck,
         TDI     => jp_tdi,
         TMS     => open,
         UPDATE  => open,
         TDO     => jp_sr(0)
      );

   jp_shiftreg : process (jp_tck)
   begin
      if rising_edge(jp_tck) then
         if jp_sel = '1' and jp_capture = '1' then
            jp_sr <= jp_snap;
         elsif jp_sel = '1' and jp_shift = '1' then
            jp_sr <= jp_tdi & jp_sr(95 downto 1);
         end if;
      end if;
   end process jp_shiftreg;

   -- JTAG probe of the keyboard: JTAG instruction USER3 (0x22), then a 176 bit data register scan
   -- (LSB first) returns: 119..0: the ST keyboard matrix from keyboard.vhd (low active, column * 8 + row),
   -- 151..120: the last 4 bytes the CPU read from the keyboard ACIA (newest in 127..120),
   -- 159..152: presses of the MEGA65 key A (key 10), 167..160: presses of S (key 13),
   -- 175..168: presses of the ST matrix key A (column 4, row 5).
   kp_sample : process (main_clk)
   begin
      if rising_edge(main_clk) then
         kp_keys(main_kb_key_num_i) <= main_kb_key_pressed_n_i;
         if main_kb_key_num_i = 10 and main_kb_key_pressed_n_i = '0' and kp_keys(10) = '1' then
            kp_cnt_a <= kp_cnt_a + 1;
         end if;
         if main_kb_key_num_i = 13 and main_kb_key_pressed_n_i = '0' and kp_keys(13) = '1' then
            kp_cnt_s <= kp_cnt_s + 1;
         end if;
         kp_st_a_old <= kp_st_matrix(37);
         if kp_st_matrix(37) = '0' and kp_st_a_old = '1' then
            kp_cnt_st_a <= kp_cnt_st_a + 1;
         end if;
         kp_snap <= std_logic_vector(kp_cnt_st_a) & std_logic_vector(kp_cnt_s) & std_logic_vector(kp_cnt_a) &
                    kp_kbd_bytes & kp_st_matrix;
      end if;
   end process kp_sample;

   kp_bscan : BSCANE2
      generic map (
         JTAG_CHAIN => 3
      )
      port map (
         CAPTURE => kp_capture,
         DRCK    => open,
         RESET   => open,
         RUNTEST => open,
         SEL     => kp_sel,
         SHIFT   => kp_shift,
         TCK     => kp_tck,
         TDI     => kp_tdi,
         TMS     => open,
         UPDATE  => open,
         TDO     => kp_sr(0)
      );

   kp_shiftreg : process (kp_tck)
   begin
      if rising_edge(kp_tck) then
         if kp_sel = '1' and kp_capture = '1' then
            kp_sr <= kp_snap;
         elsif kp_sel = '1' and kp_shift = '1' then
            kp_sr <= kp_tdi & kp_sr(175 downto 1);
         end if;
      end if;
   end process kp_shiftreg;

end architecture synthesis;
