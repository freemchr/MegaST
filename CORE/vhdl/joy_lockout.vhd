----------------------------------------------------------------------------------
-- Atari ST/STe for MEGA65
--
-- Lock-out debouncer for the joystick ports
--
-- The framework's joystick debouncer is switched off (M2M/vhdl/debouncer.vhd), because
-- it swallowed the short quadrature steps of mice. Joystick switches bounce, though, and
-- one press then looks like a burst of presses. This debouncer passes every change on at
-- once (no added latency) and ignores further changes of the same pin for G_LOCK_US.
--
-- Worn joystick switches also chatter while they are held (a Suncom TAC-2 drops out several
-- times per second). With G_RELEASE_US > 0 a release is only passed on once the pin has been
-- released for that long; presses still pass at once.
--
-- Atari ST port 2026, licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity joy_lockout is
   generic (
      G_CLK_SPEED : natural;
      G_LOCK_US   : natural;
      G_RELEASE_US : natural := 0;
      G_WIDTH     : natural := 5
   );
   port (
      clk_i       : in  std_logic;
      joy_i       : in  std_logic_vector(G_WIDTH - 1 downto 0);
      joy_o       : out std_logic_vector(G_WIDTH - 1 downto 0)
   );
end entity joy_lockout;

architecture synthesis of joy_lockout is

   constant C_LOCK : natural := G_CLK_SPEED / 1000000 * G_LOCK_US;
   constant C_REL  : natural := G_CLK_SPEED / 1000000 * G_RELEASE_US;

   type t_cnt is array (0 to G_WIDTH - 1) of natural range 0 to C_LOCK;
   type t_rel is array (0 to G_WIDTH - 1) of natural range 0 to C_REL;

   signal sync1 : std_logic_vector(G_WIDTH - 1 downto 0) := (others => '0');
   signal sync2 : std_logic_vector(G_WIDTH - 1 downto 0) := (others => '0');
   signal state : std_logic_vector(G_WIDTH - 1 downto 0) := (others => '0');
   signal cnt   : t_cnt := (others => 0);
   signal rel   : t_rel := (others => 0);

begin

   lock_proc : process(clk_i)
   begin
      if rising_edge(clk_i) then
         sync1 <= joy_i;
         sync2 <= sync1;
         for i in 0 to G_WIDTH - 1 loop
            -- rel counts how long the pin has been released (joy_i is high active: '1' = pressed)
            if sync2(i) = '1' then
               rel(i) <= 0;
            elsif rel(i) /= C_REL then
               rel(i) <= rel(i) + 1;
            end if;

            if cnt(i) /= 0 then
               cnt(i) <= cnt(i) - 1;
            elsif sync2(i) /= state(i) and (sync2(i) = '1' or rel(i) = C_REL) then
               state(i) <= sync2(i);
               cnt(i)   <= C_LOCK;
            end if;
         end loop;
      end if;
   end process lock_proc;

   joy_o <= state;

end architecture synthesis;
