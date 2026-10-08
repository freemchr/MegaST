-- GHDL test of keyboard.vhd: numeric keypad via the MEGA key (MEGA + digit, MEGA + Shift + 8/9 = ( ),
-- MEGA + Return = keypad Enter) and the normal mapping of the same keys without MEGA.
-- Menu "Keyboard as printed": digits and symbols as printed on the MEGA65 keys; a monitor checks that the
-- ST never sees a symbol key together with the wrong Shift state (C_SETTLE).
-- Shift + F5/F9 = F6/F10: the ST never sees F6/F10 together with Shift (issue #16).
library ieee; use ieee.std_logic_1164.all;
entity tb_keyboard is end entity;
architecture sim of tb_keyboard is
  constant K_RETURN : natural := 1;
  constant K_1      : natural := 56;
  constant K_8      : natural := 27;
  constant K_LSHIFT : natural := 15;
  constant K_MEGA   : natural := 61;
  constant K_2      : natural := 59;
  constant K_7      : natural := 24;
  constant K_PLUS   : natural := 40;
  constant K_AT     : natural := 46;
  constant K_COLON  : natural := 45;
  constant K_GBP    : natural := 48;
  constant K_A      : natural := 10;
  constant K_3      : natural := 8;
  constant K_ALEFT  : natural := 57;
  constant K_F5     : natural := 6;
  constant K_F9     : natural := 68;
  type key_list is array(natural range <>) of natural;

  function st(col : natural; row : natural) return natural is begin return col * 8 + row; end function;

  signal clk     : std_logic := '0';
  signal key_num : integer range 0 to 79 := 0;
  signal pressed : std_logic_vector(79 downto 0) := (others => '1');
  signal key_n   : std_logic;
  signal matrix  : std_logic_vector(119 downto 0);
  signal done    : boolean := false;
  signal printed : std_logic := '0';
  signal uk      : std_logic := '0';
  -- monitor: key mon_key must never be pressed with (mon_shift = '1') or without (mon_shift = '0') Shift
  signal mon_key   : integer := -1;
  signal mon_shift : std_logic := '0';
begin
  clk <= not clk after 5 ns when not done;
  key_n <= pressed(key_num);

  dut : entity work.keyboard generic map (G_CLK_SPEED => 1000) port map (
    clk_main_i => clk, key_num_i => key_num, key_pressed_n_i => key_n, as_printed_i => printed, uk_i => uk,
    st_matrix_n_o => matrix);

  -- The IKBD scans the matrix column by column, so it can still see the old Shift state when the key appears
  -- in the same clock cycle: the key must also not come within C_GAP cycles after the wrong Shift state.
  monitor : process(clk)
    constant C_GAP : natural := 10;   -- half of C_SETTLE (20 cycles with G_CLK_SPEED = 1000)
    variable sh    : std_logic;
    variable since : natural := C_GAP;
  begin
    if rising_edge(clk) and mon_key >= 0 then
      sh := not (matrix(st(1, 5)) and matrix(st(3, 7)));
      assert not (matrix(mon_key) = '0' and (sh = mon_shift or since < C_GAP))
        report "ST sees the key with (or right after) the wrong Shift state" severity failure;
      if sh = mon_shift then since := 0; elsif since < C_GAP then since := since + 1; end if;
    end if;
  end process;

  scan : process(clk) begin
    if rising_edge(clk) then key_num <= (key_num + 1) mod 80; end if;
  end process;

  test : process
    procedure press(keys : key_list) is
    begin
      pressed <= (others => '1');
      for i in keys'range loop pressed(keys(i)) <= '0'; end loop;
      wait for 3 us;   -- a few complete keyboard scans
    end procedure;
    procedure expect(keys : key_list; name : string) is
      variable m : std_logic_vector(119 downto 0) := (others => '1');
    begin
      for i in keys'range loop m(keys(i)) := '0'; end loop;
      assert matrix = m report name & ": wrong ST matrix" severity failure;
      report name & ": ok";
    end procedure;
  begin
    wait for 100 ns;
    press((0 => 10));                    expect((0 => st(4, 5)),  "A");
    press((0 => 13));                    expect((0 => st(5, 5)),  "S");
    press((0 => K_8));                   expect((0 => st(8, 1)),  "8");
    press((K_MEGA, K_8));                expect((0 => st(13, 3)), "MEGA+8 = keypad 8");
    press((K_MEGA, K_1));                expect((0 => st(12, 6)), "MEGA+1 = keypad 1");
    press((K_MEGA, K_LSHIFT, K_8));      expect((0 => st(13, 0)), "MEGA+Shift+8 = keypad (");
    press((K_LSHIFT, K_8));              expect((st(1, 5), st(8, 1)), "Shift+8");
    press((K_MEGA, K_RETURN));           expect((0 => st(14, 7)), "MEGA+Return = keypad Enter");
    press((0 => K_RETURN));              expect((0 => st(11, 5)), "Return");
    press((0 => K_MEGA));                expect((0 to -1 => 0), "MEGA alone");

    -- function keys (issue #16): F6 must never come with Shift, F5 never without Shift while it is held
    press((0 => K_F5));                  expect((0 => st(5, 0)), "F5");
    press((0 to -1 => 0));
    mon_key <= st(6, 0); mon_shift <= '1';
    press((0 => K_LSHIFT));              expect((0 => st(1, 5)), "Shift alone");
    press((K_LSHIFT, K_F5));             expect((0 => st(6, 0)), "Shift held, then F5 = F6 (Shift hidden)");
    press((0 => K_LSHIFT));              expect((0 => st(1, 5)), "F5 released, Shift still held");
    press((0 to -1 => 0));
    press((0 => K_F5));                  expect((0 => st(5, 0)), "F5 held");
    press((K_LSHIFT, K_F5));             expect((0 => st(6, 0)), "F5 held, then Shift = F6");
    press((0 to -1 => 0));
    mon_key <= st(10, 0);
    press((0 => K_LSHIFT));
    press((K_LSHIFT, K_F9));             expect((0 => st(10, 0)), "Shift held, then F9 = F10");
    press((0 to -1 => 0));
    mon_key <= -1;

    -- keyboard as printed (the monitor watches every transition)
    printed <= '1';
    press((0 => K_2));                   expect((0 => st(5, 1)), "printed: 2");
    mon_key <= st(11, 6); mon_shift <= '0';      -- " is ST Shift+': the ' key must not come without Shift
    press((K_LSHIFT, K_2));              expect((st(11, 6), st(1, 5)), "printed: Shift+2 = double quote (ST Shift+')");
    press((0 => K_LSHIFT));              expect((0 => st(1, 5)), "printed: Shift alone");
    press((K_LSHIFT, K_2));              expect((st(11, 6), st(1, 5)), "printed: Shift held, then 2");
    press((0 to -1 => 0));               -- release all keys before the monitor changes
    mon_key <= st(11, 6); mon_shift <= '1';      -- ' must not come with Shift
    press((K_LSHIFT, K_7));              expect((0 => st(11, 6)), "printed: Shift+7 = quote (ST ', Shift hidden)");
    mon_key <= st(10, 1); mon_shift <= '0';      -- = must never come without Shift
    press((0 => K_PLUS));                expect((st(10, 1), st(1, 5)), "printed: + (ST Shift+=)");
    mon_key <= -1;
    press((0 => K_AT));                  expect((st(5, 1), st(1, 5)), "printed: @ (ST Shift+2)");
    press((K_LSHIFT, K_COLON));          expect((0 => st(10, 3)), "printed: Shift+: = [");
    press((0 => K_COLON));               expect((st(10, 5), st(1, 5)), "printed: : (ST Shift+;)");
    press((0 => K_GBP));                 expect((0 => st(11, 4)), "printed: Pound = backslash");
    press((K_LSHIFT, K_A));              expect((st(1, 5), st(4, 5)), "printed: Shift+A");
    press((K_MEGA, K_PLUS));             expect((0 => st(14, 5)), "printed: MEGA++ = keypad +");
    -- UK TOS
    uk <= '1';
    press((K_LSHIFT, K_2));              expect((st(5, 1), st(1, 5)), "printed UK: Shift+2 = double quote (ST Shift+2)");
    press((0 => K_AT));                  expect((st(11, 6), st(1, 5)), "printed UK: @ (ST Shift+')");
    press((0 to -1 => 0));
    mon_key <= st(11, 4); mon_shift <= '1';      -- # (US \ key) must not come with Shift
    press((K_LSHIFT, K_3));              expect((0 => st(11, 4)), "printed UK: Shift+3 = # (ST # key)");
    mon_key <= -1;
    press((0 => K_GBP));                 expect((0 => st(4, 6)), "printed UK: Pound = backslash (ISO key)");
    press((K_LSHIFT, K_ALEFT));          expect((st(11, 4), st(1, 5)), "printed UK: Shift+Arrow left = ~");
    uk <= '0';
    printed <= '0';
    press((0 => K_PLUS));                expect((0 => st(9, 2)), "positional: + (ST -)");
    done <= true; wait;
  end process;
end architecture;
