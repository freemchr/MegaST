----------------------------------------------------------------------------------
-- Atari ST/STe for MEGA65 (MegaST)
--
-- Commodore 1351 mouse (proportional mode) to MiSTer PS/2 mouse events
--
-- The 1351 reports its position modulo 64 in bits 6..1 of the POTX/POTY values
-- (bit 0 is noise). Every 10 ms the difference to the previous position is
-- added to an accumulator and sent as a MiSTer "ps2_mouse" event to the IKBD
-- emulation (AtariST_MiSTer/rtl/ikbd/ps2.sv), which generates the quadrature
-- signals of an Atari mouse. The IKBD emulation handles at most ~20 steps per
-- event, so larger movements are sent over several events.
--
-- Buttons: left = fire (joystick pin 6), right = up (joystick pin 1)
--
-- The M2M framework delivers inverted pot values (255 - value).
--
-- This machine is based on AtariST_MiSTer
-- Powered by MiSTer2MEGA65
-- MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mouse1351 is
   generic (
      G_CLK_SPEED    : natural
   );
   port (
      clk_i          : in  std_logic;
      enable_i       : in  std_logic;
      pot_x_n_i      : in  std_logic_vector(7 downto 0);   -- as delivered by the M2M framework
      pot_y_n_i      : in  std_logic_vector(7 downto 0);
      fire_n_i       : in  std_logic;                      -- left button
      up_n_i         : in  std_logic;                      -- right button
      ps2_mouse_o    : out std_logic_vector(24 downto 0)
   );
end entity mouse1351;

architecture synthesis of mouse1351 is

   constant C_TICK     : natural := G_CLK_SPEED / 100;     -- 10 ms
   constant C_MAX_STEP : integer := 20;

   signal tick_cnt     : natural range 0 to C_TICK - 1 := 0;
   signal old_x        : unsigned(5 downto 0);
   signal old_y        : unsigned(5 downto 0);
   signal acc_x        : integer range -1024 to 1023 := 0;
   signal acc_y        : integer range -1024 to 1023 := 0;
   signal buttons      : std_logic_vector(1 downto 0) := "00";
   signal strobe       : std_logic := '0';
   signal first        : std_logic := '1';

   -- signed difference of two 6 bit positions (wrap around)
   function delta(new_pos : unsigned(5 downto 0); old_pos : unsigned(5 downto 0)) return integer is
      variable d : signed(5 downto 0);
   begin
      d := signed(new_pos - old_pos);
      return to_integer(d);
   end function delta;

   function clamp(v : integer) return integer is
   begin
      if v > C_MAX_STEP then
         return C_MAX_STEP;
      elsif v < -C_MAX_STEP then
         return -C_MAX_STEP;
      else
         return v;
      end if;
   end function clamp;

begin

   mouse_proc : process(clk_i)
      variable pos_x : unsigned(5 downto 0);
      variable pos_y : unsigned(5 downto 0);
      variable ax    : integer range -1024 to 1023;
      variable ay    : integer range -1024 to 1023;
      variable sx    : integer range -C_MAX_STEP to C_MAX_STEP;
      variable sy    : integer range -C_MAX_STEP to C_MAX_STEP;
      variable btn   : std_logic_vector(1 downto 0);
   begin
      if rising_edge(clk_i) then
         if tick_cnt = C_TICK - 1 then
            tick_cnt <= 0;

            pos_x := unsigned(not pot_x_n_i(6 downto 1));
            pos_y := unsigned(not pot_y_n_i(6 downto 1));
            btn   := (not up_n_i) & (not fire_n_i);

            if first = '1' then
               ax := 0;
               ay := 0;
               first <= '0';
            else
               ax := acc_x + delta(pos_x, old_x);
               ay := acc_y + delta(pos_y, old_y);
            end if;
            old_x <= pos_x;
            old_y <= pos_y;

            sx := clamp(ax);
            sy := clamp(ay);
            acc_x <= ax - sx;
            acc_y <= ay - sy;

            -- send an event if something changed
            if enable_i = '1' and (sx /= 0 or sy /= 0 or btn /= buttons) then
               buttons <= btn;
               ps2_mouse_o(23 downto 16) <= std_logic_vector(to_signed(sy, 8));   -- PS/2: up is positive
               ps2_mouse_o(15 downto 8)  <= std_logic_vector(to_signed(sx, 8));
               ps2_mouse_o(7 downto 0)   <= "00" &
                                            std_logic_vector(to_signed(sy, 9)(8 downto 8)) &
                                            std_logic_vector(to_signed(sx, 9)(8 downto 8)) &
                                            "10" & btn;
               strobe <= not strobe;
            end if;

            if enable_i = '0' then
               acc_x <= 0;
               acc_y <= 0;
            end if;
         else
            tick_cnt <= tick_cnt + 1;
         end if;

         -- the strobe toggles one clock cycle after the data has been updated
         ps2_mouse_o(24) <= strobe;
      end if;
   end process mouse_proc;

end architecture synthesis;
