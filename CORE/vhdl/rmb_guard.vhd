----------------------------------------------------------------------------------
-- Atari ST/STe for MEGA65 (MegaST)
--
-- Right mouse button on pin 9 (a pot line) of the mouse port
--
-- The pot inputs of the MEGA65 have no pull-up, so an open pin 9 reads as pressed, just like a
-- pressed button: a USB mouse adapter like the mouSTer (issue #17) or a joystick in the mouse port
-- held the right button down. An Atari or Amiga mouse pulls the pin up while the button is released.
-- So the button only counts after pin 9 was released for G_ARM_MS; pressed for G_DISARM_MS or a
-- change of the port (disarm_i) needs that release again (e.g. the mouse was replaced by an adapter).
--
-- This machine is based on AtariST_MiSTer
-- Powered by MiSTer2MEGA65
-- MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity rmb_guard is
   generic (
      G_CLK_SPEED : natural;
      G_ARM_MS    : natural := 50;
      G_DISARM_MS : natural := 10_000
   );
   port (
      clk_i     : in  std_logic;
      disarm_i  : in  std_logic;                   -- e.g. the mouse port changed
      pin_i     : in  std_logic;                   -- pin 9 reads pressed (low or open)
      rmb_o     : out std_logic                    -- right button pressed
   );
end entity rmb_guard;

architecture synthesis of rmb_guard is

   constant C_ARM    : natural := G_CLK_SPEED / 1000 * G_ARM_MS;
   constant C_DISARM : natural := G_CLK_SPEED / 1000 * G_DISARM_MS;

   signal armed : std_logic := '0';
   signal cnt   : natural range 0 to C_DISARM := 0;

begin

   rmb_o <= pin_i and armed;

   process(clk_i)
   begin
      if rising_edge(clk_i) then
         if pin_i = armed then
            -- released while disarmed, or pressed while armed
            if (armed = '0' and cnt = C_ARM) or cnt = C_DISARM then
               armed <= not armed;
               cnt   <= 0;
            else
               cnt   <= cnt + 1;
            end if;
         else
            cnt <= 0;
         end if;

         if disarm_i = '1' then
            armed <= '0';
            cnt   <= 0;
         end if;
      end if;
   end process;

end architecture synthesis;
