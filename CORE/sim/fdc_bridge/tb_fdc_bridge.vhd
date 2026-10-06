-- GHDL test of fdc_bridge.vhd: QNICE reads each drive's sector buffer through sd_buff_din. The
-- firmware reads the data of a write request before it raises sd_ack (VD_UB_WRITE, HANDLE_DRV_WR),
-- so every drive must return its own buffer whether its sd_ack is low or high. Issue #11: the hard
-- disks (drives 2, 3) returned the floppy buffer (drive 0) while sd_ack was low, so every sector
-- the ST wrote to a hard disk image was filled with floppy data.
library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
library work; use work.vdrives_pkg.all;
entity tb_fdc_bridge is end entity;
architecture sim of tb_fdc_bridge is
  signal qclk, mclk : std_logic := '0';
  signal ack    : vd_std_array(3 downto 0) := (others => '0');
  signal addr   : std_logic_vector(13 downto 0) := (others => '0');
  signal din    : vd_vec_array(3 downto 0)(7 downto 0);
  signal lba    : vd_vec_array(3 downto 0)(31 downto 0);
  signal rd, wr : vd_std_array(3 downto 0);
  signal m_addr : std_logic_vector(7 downto 0);
  signal m_din  : std_logic_vector(63 downto 0);
  signal m_dout : std_logic_vector(15 downto 0);
  signal m_ack  : std_logic_vector(3 downto 0);
  signal m_wr   : std_logic;
  signal done   : boolean := false;
  -- byte of drive d at buffer address a: distinct for every drive and address
  function pattern(d, a : natural) return std_logic_vector is
  begin
    return std_logic_vector(to_unsigned(d * 64 + (a mod 64), 8));
  end function;
begin
  qclk <= not qclk after 10 ns when not done;     -- 50 MHz (QNICE)
  mclk <= not mclk after 15.6 ns when not done;   -- 32 MHz (core)

  -- sector buffers of the clients with a registered output (floppy: drives 0, 1, ACSI: 2, 3)
  buffers : process(mclk)
  begin
    if rising_edge(mclk) then
      for d in 0 to 3 loop
        m_din(16 * d + 15 downto 16 * d) <= pattern(d, 2 * to_integer(unsigned(m_addr)) + 1) &
                                            pattern(d, 2 * to_integer(unsigned(m_addr)));
      end loop;
    end if;
  end process;

  dut : entity work.fdc_bridge
    generic map (G_VDNUM => 4)
    port map (
      qnice_clk_i => qclk, qnice_rst_i => '0', qnice_sd_lba_o => lba, qnice_sd_rd_o => rd,
      qnice_sd_wr_o => wr, qnice_sd_ack_i => ack, qnice_buff_addr_i => addr,
      qnice_buff_dout_i => x"00", qnice_buff_din_o => din, qnice_buff_wr_i => '0',
      main_clk_i => mclk, main_sd_lba_i => (others => '0'), main_sd_rd_i => "0000",
      main_sd_wr_i => "0000", main_sd_ack_o => m_ack, main_buff_addr_o => m_addr,
      main_buff_dout_o => m_dout, main_buff_din_i => m_din, main_buff_wr_o => m_wr);

  test : process
    variable errors : natural := 0;
  begin
    for acked in 0 to 4 loop               -- 4: no drive acknowledged
      ack <= (others => '0');
      if acked < 4 then ack(acked) <= '1'; end if;
      for a in 0 to 5 loop
        addr <= std_logic_vector(to_unsigned(a, 14));
        wait for 1 us;                     -- longer than the C_VD_DIN_WAIT wait states
        for d in 0 to 3 loop
          if din(d) /= pattern(d, a) then
            report "drive " & integer'image(d) & ", address " & integer'image(a) & ", ack of drive " &
                   integer'image(acked) & ": got " & to_hstring(din(d)) & ", expected " &
                   to_hstring(pattern(d, a)) severity error;
            errors := errors + 1;
          end if;
        end loop;
      end loop;
    end loop;
    if errors = 0 then
      report "OK: every drive returns its own sector buffer, with and without sd_ack";
    else
      report "FAIL: " & integer'image(errors) & " wrong bytes" severity failure;
    end if;
    done <= true;
    wait;
  end process;
end architecture;
