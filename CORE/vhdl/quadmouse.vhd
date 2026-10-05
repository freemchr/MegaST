----------------------------------------------------------------------------------
-- Atari ST/STe for MEGA65 (MegaST)
--
-- Quadrature mouse (Amiga mouse in the ST's pin order) to MiSTer PS/2 mouse events
--
-- The IKBD polls the mouse pins in software and loses steps of fast mice (optical
-- mice have several times the resolution of an Atari mouse). This decoder runs at
-- the core clock and never misses a step. Every 10 ms the accumulated movement is
-- sent as a MiSTer "ps2_mouse" event to the IKBD emulation (AtariST_MiSTer/rtl/
-- ikbd/ps2.sv), which generates the quadrature signals of an Atari mouse at a rate
-- the IKBD can follow (at most ~20 steps per event, larger movements are sent over
-- several events, see mouse1351.vhd).
--
-- Input: high active, ST pin order (bit 0 = XB, 1 = XA, 2 = YA, 3 = YB, 4 = left
-- button, 5 = right button). The Amiga's right button is on pin 9 (a pot line); the
-- caller derives it from the pot reading. A step counts in the same direction as the ps2.sv generator would
-- produce it, so the mouse moves exactly like on the direct (raw) path.
--
-- This machine is based on AtariST_MiSTer
-- Powered by MiSTer2MEGA65
-- MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity quadmouse is
   generic (
      G_CLK_SPEED    : natural
   );
   port (
      clk_i          : in  std_logic;
      enable_i       : in  std_logic;
      st_pins_i      : in  std_logic_vector(5 downto 0);   -- high active, ST pin order (see above)
      ps2_mouse_o    : out std_logic_vector(24 downto 0)
   );
end entity quadmouse;

architecture synthesis of quadmouse is

   constant C_TICK     : natural := G_CLK_SPEED / 100;     -- 10 ms
   constant C_FILTER   : natural := G_CLK_SPEED / 500000;  -- 2 us: a pin must be stable that long
   constant C_MAX_STEP : integer := 20;
   constant C_MAX_ACC  : integer := 1000;

   signal sync1        : std_logic_vector(5 downto 0) := (others => '0');
   signal sync2        : std_logic_vector(5 downto 0) := (others => '0');
   signal cand         : std_logic_vector(5 downto 0) := (others => '0');
   signal stable_cnt   : natural range 0 to C_FILTER := 0;
   signal pins         : std_logic_vector(5 downto 0) := (others => '0');
   signal pins_valid   : std_logic := '0';

   signal tick_cnt     : natural range 0 to C_TICK - 1 := 0;
   signal acc_x        : integer range -C_MAX_ACC to C_MAX_ACC := 0;
   signal acc_y        : integer range -C_MAX_ACC to C_MAX_ACC := 0;
   signal buttons      : std_logic_vector(1 downto 0) := "00";
   signal strobe       : std_logic := '0';
   signal ps2_data     : std_logic_vector(23 downto 0) := (others => '0');

   function clamp(v : integer; m : integer) return integer is
   begin
      if v > m then
         return m;
      elsif v < -m then
         return -m;
      else
         return v;
      end if;
   end function clamp;

   -- one quadrature step of the pair (a, b): +1 if (a, b) became (b_old, not a_old)
   -- (ps2.sv's positive direction), -1 for the reverse, 0 otherwise
   function step(a_old, b_old, a_new, b_new : std_logic) return integer is
   begin
      if a_new = b_old and b_new = not a_old then
         return 1;
      elsif a_new = not b_old and b_new = a_old then
         return -1;
      else
         return 0;
      end if;
   end function step;

begin

   mouse_proc : process(clk_i)
      variable ax  : integer range -C_MAX_ACC - 1 to C_MAX_ACC + 1;
      variable ay  : integer range -C_MAX_ACC - 1 to C_MAX_ACC + 1;
      variable sx  : integer range -C_MAX_STEP to C_MAX_STEP;
      variable sy  : integer range -C_MAX_STEP to C_MAX_STEP;
      variable btn : std_logic_vector(1 downto 0);
   begin
      if rising_edge(clk_i) then
         sync1 <= st_pins_i;
         sync2 <= sync1;

         ax := acc_x;
         ay := acc_y;

         -- glitch filter: take over the pins once they were stable for C_FILTER cycles
         if sync2 /= cand then
            cand       <= sync2;
            stable_cnt <= 0;
         elsif stable_cnt /= C_FILTER then
            stable_cnt <= stable_cnt + 1;
         elsif pins_valid = '0' then
            -- first stable state after power-up: reference, no step
            pins       <= cand;
            pins_valid <= '1';
         elsif cand /= pins then
            pins <= cand;
            -- X: XB = bit 0, XA = bit 1; Y: YA = bit 2, YB = bit 3
            ax := clamp(acc_x + step(pins(0), pins(1), cand(0), cand(1)), C_MAX_ACC);
            ay := clamp(acc_y + step(pins(2), pins(3), cand(2), cand(3)), C_MAX_ACC);
         end if;

         if tick_cnt = C_TICK - 1 then
            tick_cnt <= 0;
            btn := pins(5) & pins(4);
            sx  := clamp(ax, C_MAX_STEP);
            sy  := clamp(ay, C_MAX_STEP);
            ax  := ax - sx;
            ay  := ay - sy;

            -- send an event if something changed; ps2.sv negates the PS/2 y value
            if enable_i = '1' and (sx /= 0 or sy /= 0 or btn /= buttons) then
               buttons <= btn;
               ps2_data(23 downto 16) <= std_logic_vector(to_signed(-sy, 8));
               ps2_data(15 downto 8)  <= std_logic_vector(to_signed(sx, 8));
               ps2_data(7 downto 0)   <= "00" &
                                            std_logic_vector(to_signed(-sy, 9)(8 downto 8)) &
                                            std_logic_vector(to_signed(sx, 9)(8 downto 8)) &
                                            "10" & btn;
               strobe <= not strobe;
            end if;
         else
            tick_cnt <= tick_cnt + 1;
         end if;

         if enable_i = '0' then
            ax := 0;
            ay := 0;
         end if;
         acc_x <= ax;
         acc_y <= ay;

         -- the strobe toggles one clock cycle after the data has been updated
         ps2_mouse_o(24) <= strobe;
      end if;
   end process mouse_proc;

   ps2_mouse_o(23 downto 0) <= ps2_data;

end architecture synthesis;
