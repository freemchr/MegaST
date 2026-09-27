-------------------------------------------------------------------------------------------------------------
-- Atari ST/STe for MEGA65
--
-- Clock Generator using the Xilinx specific MMCME2_ADV:
--
--   The Atari ST core expects three phase aligned clocks (see AtariST_MiSTer/rtl/pll):
--
--      MiSTer         MEGA65 (this file)
--      96.254922 MHz  96.250000 MHz  SDRAM clock
--      32.084967 MHz  32.083333 MHz  system clock (main clock)
--       2.005310 MHz   2.005208 MHz  IKBD clock
--
--   VCO = 100 MHz * 9.625 = 962.5 MHz
--   CLKOUT0 = VCO / 10       = 96.25 MHz
--   CLKOUT1 = VCO / 30       = 32.083 MHz
--   CLKOUT6 = VCO / 60       = 16.042 MHz (only used as cascade source for CLKOUT4)
--   CLKOUT4 = CLKOUT6 / 8    =  2.005 MHz (CLKOUT4_CASCADE)
--
--   The deviation from the real PAL Atari ST clock (32.084988 MHz) is about 50 ppm.
--
-- MiSTer2MEGA65 done by sy2002 and MJoergen in 2022 and licensed under GPL v3
-- Atari ST port 2026, licensed under GPL v3
-------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library unisim;
use unisim.vcomponents.all;

library xpm;
use xpm.vcomponents.all;

entity clk is
   port (
      sys_clk_i       : in  std_logic;   -- expects 100 MHz

      main_clk_o      : out std_logic;   -- 32.083 MHz main clock
      main_rst_o      : out std_logic;   -- main's reset, synchronized
      sdram_clk_o     : out std_logic;   -- 96.25 MHz SDRAM clock
      ikbd_clk_o      : out std_logic    -- 2.005 MHz IKBD clock
   );
end entity clk;

architecture rtl of clk is

signal clkfb             : std_logic;
signal clkfb_mmcm        : std_logic;
signal sdram_clk_mmcm    : std_logic;
signal main_clk_mmcm     : std_logic;
signal ikbd_clk_mmcm     : std_logic;
signal main_clk          : std_logic;

signal main_locked       : std_logic;

begin

   i_clk_main : MMCME2_ADV
      generic map (
         BANDWIDTH            => "OPTIMIZED",
         CLKOUT4_CASCADE      => TRUE,
         COMPENSATION         => "ZHOLD",
         STARTUP_WAIT         => FALSE,
         CLKIN1_PERIOD        => 10.0,       -- INPUT @ 100 MHz
         REF_JITTER1          => 0.010,
         DIVCLK_DIVIDE        => 1,
         CLKFBOUT_MULT_F      => 9.625,      -- 962.5 MHz
         CLKFBOUT_PHASE       => 0.000,
         CLKFBOUT_USE_FINE_PS => FALSE,
         CLKOUT0_DIVIDE_F     => 10.000,     -- 96.25 MHz
         CLKOUT0_PHASE        => 0.000,
         CLKOUT0_DUTY_CYCLE   => 0.500,
         CLKOUT0_USE_FINE_PS  => FALSE,
         CLKOUT1_DIVIDE       => 30,         -- 32.083 MHz
         CLKOUT1_PHASE        => 0.000,
         CLKOUT1_DUTY_CYCLE   => 0.500,
         CLKOUT1_USE_FINE_PS  => FALSE,
         CLKOUT4_DIVIDE       => 8,          -- 16.042 MHz / 8 = 2.005 MHz
         CLKOUT4_PHASE        => 0.000,
         CLKOUT4_DUTY_CYCLE   => 0.500,
         CLKOUT4_USE_FINE_PS  => FALSE,
         CLKOUT6_DIVIDE       => 60,         -- 16.042 MHz
         CLKOUT6_PHASE        => 0.000,
         CLKOUT6_DUTY_CYCLE   => 0.500,
         CLKOUT6_USE_FINE_PS  => FALSE
      )
      port map (
         -- Output clocks
         CLKFBOUT            => clkfb_mmcm,
         CLKOUT0             => sdram_clk_mmcm,
         CLKOUT1             => main_clk_mmcm,
         CLKOUT4             => ikbd_clk_mmcm,
         -- Input clock control
         CLKFBIN             => clkfb,
         CLKIN1              => sys_clk_i,
         CLKIN2              => '0',
         -- Tied to always select the primary input clock
         CLKINSEL            => '1',
         -- Ports for dynamic reconfiguration
         DADDR               => (others => '0'),
         DCLK                => '0',
         DEN                 => '0',
         DI                  => (others => '0'),
         DO                  => open,
         DRDY                => open,
         DWE                 => '0',
         -- Ports for dynamic phase shift
         PSCLK               => '0',
         PSEN                => '0',
         PSINCDEC            => '0',
         PSDONE              => open,
         -- Other control and status signals
         LOCKED              => main_locked,
         CLKINSTOPPED        => open,
         CLKFBSTOPPED        => open,
         PWRDWN              => '0',
         RST                 => '0'
      ); -- i_clk_main

   -------------------------------------------------------------------------------------
   -- Output buffering
   -------------------------------------------------------------------------------------

   clkfb_bufg : BUFG
      port map (
         I => clkfb_mmcm,
         O => clkfb
      );

   sdram_clk_bufg : BUFG
      port map (
         I => sdram_clk_mmcm,
         O => sdram_clk_o
      );

   main_clk_bufg : BUFG
      port map (
         I => main_clk_mmcm,
         O => main_clk
      );

   ikbd_clk_bufg : BUFG
      port map (
         I => ikbd_clk_mmcm,
         O => ikbd_clk_o
      );

   main_clk_o <= main_clk;

   -------------------------------------
   -- Reset generation
   -------------------------------------

   i_xpm_cdc_async_rst_main : xpm_cdc_async_rst
      generic map (
         RST_ACTIVE_HIGH => 1,
         DEST_SYNC_FF    => 6
      )
      port map (
         src_arst  => not main_locked,   -- 1-bit input: Source reset signal.
         dest_clk  => main_clk,          -- 1-bit input: Destination clock.
         dest_arst => main_rst_o         -- 1-bit output: src_rst synchronized to the destination clock domain.
                                         -- This output is registered.
      );

end architecture rtl;

