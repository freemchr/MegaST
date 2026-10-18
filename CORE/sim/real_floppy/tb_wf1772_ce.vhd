-- Equivalence test of the WF1772IP clock enable conversion (tools/wf1772_ce.py):
-- the original IP on a 16 MHz clock and the converted IP on 32 MHz with CE at half rate get the same
-- CPU accesses and the same drive (floppy_model.vhd). Every output must be identical at every 16 MHz
-- edge. The test also checks the commands themselves: restore, seek, read sector (every byte),
-- read address, step in, force interrupt (also with no command running, issue #24).
-- The reference is the original with the bug fixes of tools/wf1772_ce.py (--fix-only).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.floppy_model_pkg.all;

library wf_orig;
library wf_ce;

entity tb_wf1772_ce is
end entity tb_wf1772_ce;

architecture sim of tb_wf1772_ce is

   constant C_PER32 : time := 31.17 ns;          -- 32.083 MHz

   signal clk32     : std_logic := '0';
   signal clk16     : std_logic := '0';
   signal ce        : std_logic := '0';
   signal resetn    : std_logic := '0';

   signal csn, rwn  : std_logic := '1';
   signal a         : std_logic_vector(1 downto 0) := "00";
   signal din       : std_logic_vector(7 downto 0) := (others => '0');

   type outs_t is record
      dout  : std_logic_vector(7 downto 0);
      den, mo, wg, wd, step, dirc, drq, intrq : std_logic;
   end record;
   signal o_orig, o_ce : outs_t;

   signal rdata_n, index_n, track0_n, wprot_n : std_logic;
   signal side_n    : std_logic := '1';
   signal head      : natural;
   signal mismatches : natural := 0;
   signal compared  : natural := 0;

begin

   -- clk16 rises together with every second rising edge of clk32 (in the same delta cycle, so both
   -- IPs sample their inputs at the same moment); ce is set half a clk32 period before these edges
   p_clk : process
   begin
      loop
         ce    <= '1';
         wait for C_PER32 / 2;
         clk32 <= '1';
         clk16 <= '1';
         wait for C_PER32 / 2;
         clk32 <= '0';
         ce    <= '0';
         wait for C_PER32 / 2;
         clk32 <= '1';
         clk16 <= '0';
         wait for C_PER32 / 2;
         clk32 <= '0';
      end loop;
   end process p_clk;

   i_orig : entity wf_orig.WF1772IP_TOP_SOC
      port map (
         CLK => clk16, RESETn => resetn, CSn => csn, RWn => rwn, A1 => a(1), A0 => a(0),
         DATA_IN => din, DATA_OUT => o_orig.dout, DATA_EN => o_orig.den,
         RDn => rdata_n, TR00n => track0_n, IPn => index_n, WPRTn => wprot_n, DDEn => '0', HDTYPE => '0',
         MO => o_orig.mo, WG => o_orig.wg, WD => o_orig.wd, STEP => o_orig.step, DIRC => o_orig.dirc,
         DRQ => o_orig.drq, INTRQ => o_orig.intrq);

   i_ce : entity wf_ce.WF1772IP_TOP_SOC
      port map (
         CLK => clk32, CE => ce, RESETn => resetn, CSn => csn, RWn => rwn, A1 => a(1), A0 => a(0),
         DATA_IN => din, DATA_OUT => o_ce.dout, DATA_EN => o_ce.den,
         RDn => rdata_n, TR00n => track0_n, IPn => index_n, WPRTn => wprot_n, DDEn => '0', HDTYPE => '0',
         MO => o_ce.mo, WG => o_ce.wg, WD => o_ce.wd, STEP => o_ce.step, DIRC => o_ce.dirc,
         DRQ => o_ce.drq, INTRQ => o_ce.intrq);

   -- the drive follows the converted IP; if the two differ, the comparison below reports it
   i_drive : entity work.floppy_model
      generic map (G_SECTORS => 3, G_TRACK_BYTES => 2000)
      port map (
         sel_n => '0', motor_n => not o_ce.mo, side_n => side_n, dir_n => not o_ce.dirc,
         step_n => not o_ce.step, rdata_n => rdata_n, index_n => index_n, track0_n => track0_n,
         wprot_n => wprot_n, head_o => head);

   -- compare just before every 16 MHz edge (the outputs of both settle after the edge)
   p_compare : process (clk32)
   begin
      if falling_edge(clk32) and resetn = '1' then
         compared <= compared + 1;
         if o_orig.mo /= o_ce.mo or o_orig.wg /= o_ce.wg or o_orig.wd /= o_ce.wd or o_orig.step /= o_ce.step or
            o_orig.dirc /= o_ce.dirc or o_orig.drq /= o_ce.drq or o_orig.intrq /= o_ce.intrq or
            o_orig.den /= o_ce.den or (o_orig.den = '1' and o_orig.dout /= o_ce.dout) then
            if mismatches < 10 then
               report "mismatch at " & time'image(now) & ": orig/ce mo " & std_logic'image(o_orig.mo) &
                      std_logic'image(o_ce.mo) & " step " & std_logic'image(o_orig.step) & std_logic'image(o_ce.step) &
                      " dirc " & std_logic'image(o_orig.dirc) & std_logic'image(o_ce.dirc) &
                      " drq " & std_logic'image(o_orig.drq) & std_logic'image(o_ce.drq) &
                      " intrq " & std_logic'image(o_orig.intrq) & std_logic'image(o_ce.intrq) &
                      " wg " & std_logic'image(o_orig.wg) & std_logic'image(o_ce.wg) &
                      " wd " & std_logic'image(o_orig.wd) & std_logic'image(o_ce.wd) &
                      " den " & std_logic'image(o_orig.den) & std_logic'image(o_ce.den) &
                      " dout " & to_hstring(o_orig.dout) & "/" & to_hstring(o_ce.dout) severity warning;
            end if;
            mismatches <= mismatches + 1;
         end if;
      end if;
   end process p_compare;

   p_cpu : process
      -- one 68000 bus cycle at 8 MHz: chip select low for 500 ns
      procedure wr(reg : natural; v : std_logic_vector(7 downto 0)) is
      begin
         a   <= std_logic_vector(to_unsigned(reg, 2));
         din <= v;
         rwn <= '0';
         wait for 125 ns;
         csn <= '0';
         wait for 500 ns;
         csn <= '1';
         wait for 125 ns;
         rwn <= '1';
         wait for 1 us;
      end procedure;
      procedure rd(reg : natural; v : out std_logic_vector(7 downto 0)) is
      begin
         a   <= std_logic_vector(to_unsigned(reg, 2));
         rwn <= '1';
         wait for 125 ns;
         csn <= '0';
         wait for 450 ns;
         v   := o_ce.dout;
         wait for 50 ns;
         csn <= '1';
         wait for 250 ns;
      end procedure;
      procedure wait_drq(t : time; what : string) is
      begin
         if o_ce.drq /= '1' then
            wait until o_ce.drq = '1' for t;
         end if;
         assert o_ce.drq = '1' report what & ": no DRQ after " & time'image(t) severity failure;
      end procedure;
      procedure wait_not_busy(t : time; st : out std_logic_vector(7 downto 0)) is
         variable v : std_logic_vector(7 downto 0);
         variable n : natural := 0;
      begin
         loop
            rd(0, v);
            exit when v(0) = '0' or n * 100 us >= t;
            wait for 100 us;
            n := n + 1;
         end loop;
         st := v;
         assert v(0) = '0' report "still busy after " & time'image(t) severity failure;
      end procedure;
      procedure wait_intrq(t : time) is
      begin
         if o_ce.intrq /= '1' then
            wait until o_ce.intrq = '1' for t;
         end if;
         assert o_ce.intrq = '1' report "no INTRQ after " & time'image(t) severity failure;
      end procedure;
      variable st, v : std_logic_vector(7 downto 0);
      variable t_fi  : time;
      variable errs  : natural;
      procedure read_sector(t, s, sec : natural) is
      begin
         wr(2, std_logic_vector(to_unsigned(sec, 8)));
         wr(0, x"88");                                  -- read sector, no spin-up
         errs := 0;
         for i in 0 to 511 loop
            wait_drq(150 ms, "read sector byte " & integer'image(i));
            rd(3, v);
            if v /= sector_byte(t, s, sec, i) then
               errs := errs + 1;
            end if;
         end loop;
         wait_intrq(10 ms);
         rd(0, st);
         report "read sector t" & integer'image(t) & " s" & integer'image(s) & " #" & integer'image(sec) &
                ": status " & to_hstring(st) & ", byte errors " & integer'image(errs);
         assert errs = 0 and (st and x"7F") = x"00" report "read sector failed" severity failure;
      end procedure;
   begin
      wait for 1 us;
      resetn <= '1';
      wait for 2 us;

      -- force interrupt with no command running, as EmuTOS does before its drive detection (issue #24):
      -- the controller must stay idle and take the next command (the original IP restarted the last one)
      wr(0, x"D0");
      rd(0, st);
      report "force interrupt from idle: status " & to_hstring(st);
      assert st(0) = '0' and st(7) = '0' report "force interrupt from idle: busy or motor on" severity failure;

      -- restore (h = 1: no spin-up wait, 6 ms step rate)
      wr(0, x"08");
      wait_intrq(600 ms);
      rd(0, st);
      report "restore: status " & to_hstring(st) & ", head " & integer'image(head);
      assert head = 0 and st(2) = '1' report "restore failed (TR00 bit)" severity failure;

      -- seek to track 2
      wr(3, x"02");
      wr(0, x"18");
      wait_intrq(100 ms);
      rd(0, st);
      rd(1, v);
      report "seek: status " & to_hstring(st) & ", head " & integer'image(head) & ", track reg " & to_hstring(v);
      assert head = 2 and v = x"02" report "seek failed" severity failure;

      read_sector(2, 0, 2);

      -- read address: track, side, sector, size (WF1772IP transfers 4 bytes, a real WD1772 also the 2 CRC
      -- bytes; known difference, see doc/real-floppy.md)
      wr(0, x"C8");
      for i in 0 to 3 loop
         wait_drq(150 ms, "read address byte " & integer'image(i));
         rd(3, v);
         report "read address byte " & integer'image(i) & " = " & to_hstring(v);
         if i = 0 then
            assert v = x"02" report "read address: wrong track " & to_hstring(v) severity failure;
         elsif i = 3 then
            assert v = x"02" report "read address: wrong size" severity failure;
         end if;
      end loop;
      wait_not_busy(10 ms, st);
      report "read address: status " & to_hstring(st);
      assert (st and x"7F") = x"00" report "read address failed" severity failure;

      -- step in (with track update), then side 1
      wr(0, x"58");
      wait_intrq(50 ms);
      rd(1, v);
      assert head = 3 and v = x"03" report "step in failed" severity failure;
      side_n <= '0';
      read_sector(3, 1, 3);

      -- force interrupt after a command: idle at once (the original IP was busy for about 7 ms)
      t_fi := now;
      wr(0, x"D0");
      wait_not_busy(10 ms, st);
      assert now - t_fi < 10 us report "force interrupt: still busy" severity failure;
      report "force interrupt: status " & to_hstring(st) & " at " & time'image(now);

      wait for 100 us;
      report "compared " & integer'image(compared) & " clock edges, mismatches " & integer'image(mismatches);
      assert mismatches = 0 report "the converted IP differs from the original" severity failure;
      report "WF1772IP clock enable conversion: all tests passed";
      std.env.finish;
   end process p_cpu;

end architecture sim;
