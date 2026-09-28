-- QNICE-like master: sets up a write at a rising edge and ends it at the first rising edge
-- where wait = '0' (like qnice_cpu.vhd, cs_exepost_store_dst_indirect). Core side acknowledges
-- each word after a few 32 MHz cycles, like atarist_m65.sv. Checks every word arrives exactly once.
-- MANUAL = true: the TOS is loaded via the manual TOS device (menu): the loader first has to clear
-- the TOS system variables ($420-$43F, $51A-$51D) while the core is in reset (tos_loading).
library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
entity tb_tos_loader is generic (MANUAL : boolean := false); end entity;
architecture sim of tb_tos_loader is
  signal qclk, mclk : std_logic := '0';
  signal addr : std_logic_vector(27 downto 0) := (others => '0');
  signal data : std_logic_vector(15 downto 0) := (others => '0');
  signal ce, we, wt : std_logic := '0';
  signal cdata : std_logic_vector(15 downto 0);
  signal m_addr : std_logic_vector(23 downto 1);
  signal m_data : std_logic_vector(15 downto 0);
  signal m_strobe, m_ack : std_logic := '0';
  signal t192, cl, cld, tld : std_logic;
  signal ce_auto, ce_man : std_logic;
  signal done : boolean := false;
  constant N : integer := 4096;   -- bytes
begin
  qclk <= not qclk after 10 ns when not done;      -- 50 MHz
  mclk <= not mclk after 15.6 ns when not done;    -- 32 MHz

  dut : entity work.tos_loader port map (
    qnice_clk_i => qclk, qnice_rst_i => '0', qnice_addr_i => addr, qnice_data_i => data,
    qnice_ce_i => ce_auto, qnice_cart_ce_i => '0', qnice_tosm_ce_i => ce_man, qnice_we_i => we, qnice_wait_o => wt,
    qnice_csr_data_o => cdata,
    main_clk_i => mclk, main_dio_addr_o => m_addr, main_dio_data_o => m_data, main_dio_strobe_o => m_strobe,
    main_dio_ack_i => m_ack, main_tos192k_o => t192, main_cart_loaded_o => cl, main_cart_loading_o => cld,
    main_tos_loading_o => tld);
  ce_auto <= ce when not MANUAL else '0';
  ce_man  <= ce when MANUAL else '0';

  -- core: ack every word after 16 cycles (roughly one ST bus cycle), check address/data
  core : process
    variable cnt : integer := 0;
    variable exp : integer := 0;
    variable dups : integer := 0;
    variable clr : integer := 0;
    variable clr_exp : integer;
  begin
    wait until rising_edge(mclk);
    if m_strobe /= m_ack then
      cnt := cnt + 1;
      if cnt = 16 and MANUAL and clr < 18 then
        -- the system variables are cleared first, while the core is in reset
        if clr < 16 then clr_exp := 16#210# + clr; else clr_exp := 16#28D# + clr - 16; end if;
        assert tld = '1' report "clear word written while the core is not in reset" severity failure;
        assert unsigned(m_addr) = clr_exp and m_data = x"0000"
          report "wrong clear word " & integer'image(clr) & ": " & to_hstring(m_addr) & " = " & to_hstring(m_data) severity failure;
        clr := clr + 1;
        m_ack <= m_strobe; cnt := 0;
      elsif cnt = 16 and exp > 0 and unsigned(m_addr) = 16#700000# + exp - 1 then
        dups := dups + 1; m_ack <= m_strobe; cnt := 0;
        if dups mod 1000 = 0 then report integer'image(dups) & " repeated words"; end if;
      elsif cnt = 16 then
        assert unsigned(m_addr) = 16#700000# + exp report "wrong address " & integer'image(to_integer(unsigned(m_addr))) & " expected word " & integer'image(exp) severity failure;
        assert m_data = std_logic_vector(to_unsigned((2*exp) mod 256, 8)) & std_logic_vector(to_unsigned((2*exp+1) mod 256, 8))
          report "wrong data at word " & integer'image(exp) & " got " & to_hstring(m_data) severity failure;
        exp := exp + 1;
        m_ack <= m_strobe; cnt := 0;
      end if;
    end if;
    if exp = N/2 then
      if MANUAL then assert clr = 18 and tld = '1' report "clearing incomplete" severity failure; end if;
      report "all " & integer'image(exp) & " words received, " & integer'image(dups) & " repeated, " &
             integer'image(clr) & " system variable words cleared";
      done <= true; wait;
    end if;
  end process;

  -- QNICE: write byte i with value i mod 256, no gap between the writes (worst case)
  cpu : process
  begin
    if MANUAL then
      -- CSR: status = loading (the shell does this before it opens the file), then start at once:
      -- the first data words have to wait until the clearing is done
      wait until rising_edge(qclk);
      addr <= x"FFFF000"; data <= x"0001"; ce <= '1'; we <= '1';
      wait until rising_edge(qclk);
      ce <= '0'; we <= '0';
      for k in 1 to 20 loop wait until rising_edge(qclk); end loop;
    end if;
    for i in 0 to N-1 loop
      wait until rising_edge(qclk);
      addr <= std_logic_vector(to_unsigned(i, 28)); data <= x"00" & std_logic_vector(to_unsigned(i mod 256, 8));
      ce <= '1'; we <= '1';
      loop
        wait until rising_edge(qclk);
        exit when wt = '0';
      end loop;
      ce <= '0'; we <= '0';
      -- a few cycles for the next f32_fread
      for k in 1 to 3 loop wait until rising_edge(qclk); end loop;
    end loop;
    wait;
  end process;

  timeout : process begin wait for 2 ms; assert done report "TIMEOUT: loader hangs" severity failure; wait; end process;
end architecture;
