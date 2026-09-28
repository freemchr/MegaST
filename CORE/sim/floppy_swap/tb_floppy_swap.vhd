-- GHDL test of floppy_swap.vhd: mount two images, swap the drives, check that the FDC drives are
-- announced again with the right image sizes (rising edges of fdc_mounted) and that read/write
-- requests and the read-only flags are mapped to the right drives.
library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
entity tb_floppy_swap is end entity;
architecture sim of tb_floppy_swap is
  signal clk : std_logic := '0';
  signal swap : std_logic := '0';
  signal vd_mounted : std_logic_vector(1 downto 0) := "00";
  signal vd_ro : std_logic := '0';
  signal vd_size : std_logic_vector(31 downto 0) := (others => '0');
  signal vd_rd, vd_wr, fdc_mounted, fdc_ro : std_logic_vector(1 downto 0);
  signal fdc_rd, fdc_wr : std_logic_vector(1 downto 0) := "00";
  signal fdc_size : std_logic_vector(31 downto 0);
  signal done : boolean := false;
  constant SIZE_A : natural := 737280;   -- 720 kB, writable
  constant SIZE_B : natural := 368640;   -- 360 kB, read-only
  -- what the FDC latched (rising edge of fdc_mounted, like fdc1772.sv)
  type size_array is array(0 to 1) of natural;
  signal latched : size_array := (0, 0);
  signal edges   : natural := 0;
begin
  clk <= not clk after 5 ns when not done;

  dut : entity work.floppy_swap port map (
    clk_i => clk, swap_i => swap, vd_mounted_i => vd_mounted, vd_readonly_i => vd_ro, vd_size_i => vd_size,
    vd_sd_rd_o => vd_rd, vd_sd_wr_o => vd_wr, fdc_mounted_o => fdc_mounted, fdc_size_o => fdc_size,
    fdc_readonly_o => fdc_ro, fdc_sd_rd_i => fdc_rd, fdc_sd_wr_i => fdc_wr);

  fdc : process(clk)
    variable d : std_logic_vector(1 downto 0) := "00";
  begin
    if rising_edge(clk) then
      for i in 0 to 1 loop
        if d(i) = '0' and fdc_mounted(i) = '1' then
          latched(i) <= to_integer(unsigned(fdc_size)); edges <= edges + 1;
        end if;
      end loop;
      d := fdc_mounted;
    end if;
  end process;

  test : process
    procedure mount(drive : natural; size : natural; ro : std_logic) is
    begin
      wait until rising_edge(clk);
      vd_size <= std_logic_vector(to_unsigned(size, 32)); vd_ro <= ro;
      vd_mounted(drive) <= '1';
      for k in 1 to 20 loop wait until rising_edge(clk); end loop;   -- the firmware strobe is long
      vd_mounted(drive) <= '0';
      vd_size <= (others => '1'); vd_ro <= 'X';                     -- only valid during the strobe
      for k in 1 to 5 loop wait until rising_edge(clk); end loop;
    end procedure;
  begin
    mount(0, SIZE_A, '0');
    mount(1, SIZE_B, '1');
    assert latched(0) = SIZE_A and latched(1) = SIZE_B report "mount: wrong sizes" severity failure;
    assert fdc_ro = "10" report "mount: wrong read-only flags" severity failure;
    fdc_rd <= "01"; wait for 1 ns;
    assert vd_rd = "01" report "not swapped: FDC drive 0 must read from A:" severity failure;
    fdc_rd <= "00";
    report "mounted: ok";

    swap <= '1';
    for k in 1 to 10 loop wait until rising_edge(clk); end loop;
    assert edges = 4 report "swap: both drives must be announced again" severity failure;
    assert latched(0) = SIZE_B and latched(1) = SIZE_A report "swap: wrong sizes" severity failure;
    assert fdc_ro = "01" report "swap: wrong read-only flags" severity failure;
    fdc_rd <= "01"; fdc_wr <= "10"; wait for 1 ns;
    assert vd_rd = "10" and vd_wr = "01" report "swap: wrong request mapping" severity failure;
    fdc_rd <= "00"; fdc_wr <= "00";
    report "swapped: ok";

    mount(0, 1474560, '0');   -- new image in A: while swapped = FDC drive 1
    assert latched(1) = 1474560 and latched(0) = SIZE_B report "mount while swapped: wrong drive" severity failure;
    report "mount while swapped: ok";

    swap <= '0';
    for k in 1 to 10 loop wait until rising_edge(clk); end loop;
    assert latched(0) = 1474560 and latched(1) = SIZE_B and fdc_ro = "10" report "swap back: wrong" severity failure;
    report "swapped back: ok";
    done <= true; wait;
  end process;
end architecture;
