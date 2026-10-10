-- Test of rmb_guard.vhd (right mouse button on pin 9, issue #17), scaled clock: 1 kHz, i.e. 1 cycle = 1 ms
library ieee;
use ieee.std_logic_1164.all;

entity tb_rmb_guard is
end entity tb_rmb_guard;

architecture sim of tb_rmb_guard is
   signal clk    : std_logic := '0';
   signal disarm : std_logic := '0';
   signal pin    : std_logic := '1';     -- open pin: reads pressed
   signal rmb    : std_logic;
   signal done   : boolean := false;

   procedure wait_ms(n : natural; signal c : in std_logic) is
   begin
      for i in 1 to n loop
         wait until rising_edge(c);
      end loop;
   end procedure wait_ms;
begin
   clk <= not clk after 500 us when not done;

   i_dut : entity work.rmb_guard
      generic map (G_CLK_SPEED => 1000, G_ARM_MS => 50, G_DISARM_MS => 10_000)
      port map (clk_i => clk, disarm_i => disarm, pin_i => pin, rmb_o => rmb);

   test : process
   begin
      -- mouSTer / joystick: pin 9 open the whole time -> never pressed
      for i in 1 to 20_000 loop
         wait until rising_edge(clk);
         assert rmb = '0' report "open pin 9 reads as right button" severity failure;
      end loop;

      -- Atari mouse plugged in: released (pulled up), but shorter than 50 ms -> still disarmed
      pin <= '0'; wait_ms(30, clk);
      pin <= '1'; wait_ms(2, clk);
      assert rmb = '0' report "armed after a 30 ms release" severity failure;

      -- released for 60 ms -> armed, a click passes at once
      pin <= '0'; wait_ms(60, clk);
      pin <= '1'; wait for 1 ns;
      assert rmb = '1' report "click not passed after arming" severity failure;
      wait_ms(200, clk);
      assert rmb = '1' report "held button dropped" severity failure;
      pin <= '0'; wait for 1 ns;
      assert rmb = '0' report "release not passed" severity failure;

      -- short release between clicks keeps it armed
      wait_ms(5, clk);
      pin <= '1'; wait for 1 ns;
      assert rmb = '1' report "second click lost" severity failure;

      -- held for more than 10 s (adapter replaced the mouse) -> disarmed
      wait_ms(10_005, clk);
      assert rmb = '0' report "not disarmed after 10 s" severity failure;
      pin <= '0'; wait_ms(60, clk);
      pin <= '1'; wait for 1 ns;
      assert rmb = '1' report "not re-armed after release" severity failure;

      -- port change disarms
      pin <= '0'; wait_ms(5, clk);
      disarm <= '1'; wait_ms(1, clk); disarm <= '0';
      pin <= '1'; wait_ms(2, clk);
      assert rmb = '0' report "not disarmed by port change" severity failure;

      report "rmb_guard: all tests passed";
      done <= true;
      wait;
   end process test;
end architecture sim;
