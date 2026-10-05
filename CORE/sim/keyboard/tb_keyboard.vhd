-- GHDL test of keyboard.vhd: numeric keypad via the MEGA key (MEGA + digit, MEGA + Shift + 8/9 = ( ),
-- MEGA + Return = keypad Enter) and the normal mapping of the same keys without MEGA.
library ieee; use ieee.std_logic_1164.all;
entity tb_keyboard is end entity;
architecture sim of tb_keyboard is
  constant K_RETURN : natural := 1;
  constant K_1      : natural := 56;
  constant K_8      : natural := 27;
  constant K_LSHIFT : natural := 15;
  constant K_MEGA   : natural := 61;
  type key_list is array(natural range <>) of natural;

  function st(col : natural; row : natural) return natural is begin return col * 8 + row; end function;

  signal clk     : std_logic := '0';
  signal key_num : integer range 0 to 79 := 0;
  signal pressed : std_logic_vector(79 downto 0) := (others => '1');
  signal key_n   : std_logic;
  signal matrix  : std_logic_vector(119 downto 0);
  signal done    : boolean := false;
begin
  clk <= not clk after 5 ns when not done;
  key_n <= pressed(key_num);

  dut : entity work.keyboard generic map (G_CLK_SPEED => 1000) port map (
    clk_main_i => clk, key_num_i => key_num, key_pressed_n_i => key_n, st_matrix_n_o => matrix);

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
    done <= true; wait;
  end process;
end architecture;
