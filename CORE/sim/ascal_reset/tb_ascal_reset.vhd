-- Issue #26: does the HDMI picture freeze after a reset?
-- ascal (as in digital_pipeline.vhd: 16 bpp, triple buffer, downscale) + avm_decrease + avm_arbit_general,
-- on a HyperRAM-like Avalon model (one transaction at a time, random wait and read latency).
-- The input picture codes its frame number in red, so the output shows how old the picture is.
-- Two kinds of reset at random moments:
--   button: hr_rst (HyperRAM, arbiter, avm_decrease, ascal reset_na) plus the core reset (input video stops)
--   menu  : only the core reset (input video stops, the HyperRAM side keeps running)
-- A trial fails if the output picture is still old 15 output frames after the reset.
--
-- MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use work.dbg_pkg.all;   -- probe_now: the copies of ascal, avm_arbit, avm_decrease print their state

entity tb_ascal_reset is
   generic (
      G_TRIALS : natural := 40;
      G_SEED   : positive := 7;
      G_PROBE_TEST : boolean := false   -- print the probe 1 ms after power on and stop
   );
end entity tb_ascal_reset;

architecture sim of tb_ascal_reset is

   -- input video (Falcon side): 160x120, 25 MHz
   constant I_HT : natural := 200; constant I_HA : natural := 160;
   constant I_VT : natural := 135; constant I_VA : natural := 120;
   constant I_VS0 : natural := 125; constant I_VS1 : natural := 127;
   constant I_HS0 : natural := 170; constant I_HS1 : natural := 185;

   signal hr_clk, i_clk, o_clk : std_logic := '0';
   signal done : boolean := false;

   signal hr_rst   : std_logic := '1';
   signal core_rst : std_logic := '1';
   signal reset_na : std_logic;

   -- input video
   signal i_hc, i_vc : natural := 0;
   signal i_frame    : natural := 0;
   signal i_r, i_g, i_b : unsigned(7 downto 0);
   signal i_hs, i_vs, i_de : std_logic := '0';

   -- output video
   signal o_r, o_g, o_b : unsigned(7 downto 0);
   signal o_hs, o_vs, o_de : std_logic;

   -- ascal Avalon (128 bit)
   signal w_write, w_read, w_wait, w_rdv : std_logic;
   signal w_addr : std_logic_vector(18 downto 0);
   signal w_wdata, w_rdata : std_logic_vector(127 downto 0);
   signal w_be : std_logic_vector(15 downto 0);
   signal w_bc : std_logic_vector(7 downto 0);

   -- 16 bit, before the arbiter
   signal d_write, d_read, d_wait, d_rdv : std_logic;
   signal d_addr : std_logic_vector(31 downto 0) := (others => '0');
   signal d_wdata, d_rdata : std_logic_vector(15 downto 0);
   signal d_be : std_logic_vector(1 downto 0);
   signal d_bc : std_logic_vector(7 downto 0);

   -- memory side
   signal m_write, m_read, m_wait, m_rdv : std_logic;
   signal m_addr : std_logic_vector(31 downto 0);
   signal m_wdata, m_rdata : std_logic_vector(15 downto 0);
   signal m_be : std_logic_vector(1 downto 0);
   signal m_bc : std_logic_vector(7 downto 0);

   signal s_rdata : std_logic_vector(47 downto 0);
   signal s_rdv, s_wait : std_logic_vector(2 downto 0);

   -- monitor
   signal o_age       : integer := 99;   -- age of the shown picture in input frames (mod 32)
   signal o_frames    : natural := 0;
   signal rd_words    : natural := 0;

begin

   hr_clk <= not hr_clk after 5 ns    when not done;   -- 100 MHz
   i_clk  <= not i_clk  after 20 ns   when not done;   -- 25 MHz
   o_clk  <= not o_clk  after 18.5 ns when not done;   -- 27 MHz

   reset_na <= not hr_rst;   -- video_rst (MMCM lock) is 0 here

   ---------------------------------------------------------------------------
   -- Input video; stops during the core reset like the VIDEL
   ---------------------------------------------------------------------------
   p_in : process (i_clk)
   begin
      if rising_edge(i_clk) then
         if core_rst = '1' then
            i_hc <= 0; i_vc <= 0;
         else
            if i_hc = I_HT - 1 then
               i_hc <= 0;
               if i_vc = I_VT - 1 then
                  i_vc <= 0;
                  i_frame <= i_frame + 1;
               else
                  i_vc <= i_vc + 1;
               end if;
            else
               i_hc <= i_hc + 1;
            end if;
         end if;
      end if;
   end process;

   i_de <= '1' when core_rst = '0' and i_hc < I_HA and i_vc < I_VA else '0';
   i_hs <= '1' when core_rst = '0' and i_hc >= I_HS0 and i_hc < I_HS1 else '0';
   i_vs <= '1' when core_rst = '0' and i_vc >= I_VS0 and i_vc < I_VS1 else '0';
   i_r  <= to_unsigned((i_frame mod 32) * 8, 8);
   i_g  <= x"40";
   i_b  <= x"00";

   ---------------------------------------------------------------------------
   i_ascal : entity work.ascal
      generic map (
         MASK => x"f1", RAMBASE => (others => '0'), RAMSIZE => to_unsigned(65536, 32),
         INTER => false, HEADER => false, DOWNSCALE => true, DOWNSCALE_NN => true,
         BYTESWAP => true, ADAPTIVE => true, PALETTE => false, PALETTE2 => false,
         FRAC => 6, OHRES => 2048, IHRES => 1024, N_DW => 128, N_AW => 19, N_BURST => 128
      )
      port map (
         i_r => i_r, i_g => i_g, i_b => i_b, i_hs => i_hs, i_vs => i_vs, i_fl => '0',
         i_de => i_de, i_ce => '1', i_clk => i_clk,
         o_r => o_r, o_g => o_g, o_b => o_b, o_hs => o_hs, o_vs => o_vs, o_de => o_de,
         o_vbl => open, o_brd => open, o_ce => '1', o_clk => o_clk,
         o_border => x"000000", o_fb_ena => '0', o_fb_hsize => 0, o_fb_vsize => 0,
         o_fb_format => "000101", o_fb_base => x"0000_0000", o_fb_stride => (others => '0'),
         pal1_clk => '0', pal1_dw => x"000000000000", pal1_dr => open, pal1_a => "0000000",
         pal1_wr => '0', pal_n => '0', pal2_clk => '0', pal2_dw => x"000000", pal2_dr => open,
         pal2_a => "00000000", pal2_wr => '0', o_lltune => open,
         iauto => '1', himin => 0, himax => 0, vimin => 0, vimax => 0,
         i_hdmax => open, i_vdmax => open,
         run => '1', freeze => '0', mode => "01000",
         htotal => 200, hsstart => 168, hsend => 184, hdisp => 160, hmin => 0, hmax => 159,
         vtotal => 130, vsstart => 122, vsend => 124, vdisp => 120, vmin => 0, vmax => 119,
         format => "00",
         poly_clk => '0', poly_dw => (others => '0'), poly_a => (others => '0'), poly_wr => '0',
         avl_clk => hr_clk, avl_waitrequest => w_wait, avl_readdata => w_rdata,
         avl_readdatavalid => w_rdv, avl_burstcount => w_bc, avl_writedata => w_wdata,
         avl_address => w_addr, avl_write => w_write, avl_read => w_read, avl_byteenable => w_be,
         reset_na => reset_na
      );

   i_dec : entity work.avm_decrease
      generic map (
         G_SLAVE_ADDRESS_SIZE => 19, G_SLAVE_DATA_SIZE => 128,
         G_MASTER_ADDRESS_SIZE => 22, G_MASTER_DATA_SIZE => 16
      )
      port map (
         clk_i => hr_clk, rst_i => hr_rst,
         s_avm_write_i => w_write, s_avm_read_i => w_read, s_avm_address_i => w_addr,
         s_avm_writedata_i => w_wdata, s_avm_byteenable_i => w_be, s_avm_burstcount_i => w_bc,
         s_avm_readdata_o => w_rdata, s_avm_readdatavalid_o => w_rdv, s_avm_waitrequest_o => w_wait,
         m_avm_write_o => d_write, m_avm_read_o => d_read, m_avm_address_o => d_addr(21 downto 0),
         m_avm_writedata_o => d_wdata, m_avm_byteenable_o => d_be, m_avm_burstcount_o => d_bc,
         m_avm_readdata_i => d_rdata, m_avm_readdatavalid_i => d_rdv, m_avm_waitrequest_i => d_wait
      );

   -- slave 2 = ascal, 1 = core (QNICE disks), 0 = QNICE: idle here
   i_arb : entity work.avm_arbit_general
      generic map (G_NUM_SLAVES => 3, G_FREQ_HZ => 100_000_000, G_ADDRESS_SIZE => 32, G_DATA_SIZE => 16)
      port map (
         clk_i => hr_clk, rst_i => hr_rst,
         s_avm_write_i => d_write & "00", s_avm_read_i => d_read & "00",
         s_avm_address_i => d_addr & x"00000000" & x"00000000",
         s_avm_writedata_i => d_wdata & x"0000" & x"0000",
         s_avm_byteenable_i => d_be & "11" & "11",
         s_avm_burstcount_i => d_bc & x"01" & x"01",
         s_avm_readdata_o => s_rdata, s_avm_readdatavalid_o => s_rdv, s_avm_waitrequest_o => s_wait,
         m_avm_write_o => m_write, m_avm_read_o => m_read, m_avm_address_o => m_addr,
         m_avm_writedata_o => m_wdata, m_avm_byteenable_o => m_be, m_avm_burstcount_o => m_bc,
         m_avm_readdata_i => m_rdata, m_avm_readdatavalid_i => m_rdv, m_avm_waitrequest_i => m_wait
      );
   d_rdata <= s_rdata(47 downto 32);
   d_rdv   <= s_rdv(2);
   d_wait  <= s_wait(2);

   ---------------------------------------------------------------------------
   -- HyperRAM-like memory: one transaction at a time, waitrequest while busy,
   -- read data after 8..24 clocks, then one word per clock (sometimes a gap)
   ---------------------------------------------------------------------------
   p_mem : process (hr_clk)
      type mem_t is array (0 to 2**18 - 1) of std_logic_vector(15 downto 0);
      variable mem : mem_t;
      variable s1, s2 : positive := 11;
      variable r : real;
      variable busy : boolean := false;
      variable is_rd : boolean;
      variable adr, left, lat : natural;
   begin
      if rising_edge(hr_clk) then
         m_rdv <= '0';
         uniform(s1, s2, r);
         if hr_rst = '1' then
            busy := false;
            m_wait <= '1';
         elsif not busy then
            m_wait <= '0';
            if m_wait = '0' and (m_read = '1' or m_write = '1') then
               adr  := to_integer(unsigned(m_addr(17 downto 0)));
               left := to_integer(unsigned(m_bc));
               is_rd := m_read = '1';
               if m_write = '1' then
                  mem(adr) := m_wdata;
                  adr := (adr + 1) mod 2**18;
                  left := left - 1;
               end if;
               lat  := 8 + integer(r * 16.0);
               busy := left > 0;
               if is_rd or busy then
                  m_wait <= '1';
               end if;
               if not is_rd and busy then
                  m_wait <= '0';     -- accept the rest of the write burst
               end if;
            elsif r < 0.2 then
               m_wait <= '1';        -- refresh / latency: not ready now
            end if;
         else
            if is_rd then
               m_wait <= '1';
               if lat > 0 then
                  lat := lat - 1;
               elsif r > 0.05 then
                  m_rdata <= mem(adr);
                  m_rdv   <= '1';
                  adr  := (adr + 1) mod 2**18;
                  left := left - 1;
                  if left = 0 then
                     busy := false;
                     m_wait <= '0';
                  end if;
               end if;
            else
               m_wait <= '0';
               if m_write = '1' then
                  mem(adr) := m_wdata;
                  adr  := (adr + 1) mod 2**18;
                  left := left - 1;
                  if left = 0 then
                     busy := false;
                  end if;
               end if;
            end if;
         end if;
      end if;
   end process;

   ---------------------------------------------------------------------------
   -- Monitor: red of the pixel in the middle of every output frame
   ---------------------------------------------------------------------------
   p_mon : process (o_clk)
      variable ln, px : natural := 0;
      variable vs_d, de_d : std_logic := '0';
   begin
      if rising_edge(o_clk) then
         if o_vs = '1' and vs_d = '0' then
            ln := 0;
            o_frames <= o_frames + 1;
         end if;
         if o_de = '1' then
            if de_d = '0' then px := 0; ln := ln + 1; else px := px + 1; end if;
            if ln = 60 and px = 80 then
               o_age <= ((i_frame mod 32) - to_integer(o_r(7 downto 3)) + 64) mod 32;
            end if;
         end if;
         vs_d := o_vs; de_d := o_de;
      end if;
   end process;

   p_rd : process (hr_clk)
   begin
      if rising_edge(hr_clk) then
         if m_rdv = '1' then rd_words <= rd_words + 1; end if;
      end if;
   end process;


   ---------------------------------------------------------------------------
   p_main : process
      variable s1, s2 : positive := G_SEED;
      variable r : real;
      variable fails, f0 : natural := 0;
      variable kind : string(1 to 6);
      variable rd0 : natural;
      variable worst : integer;
   begin
      hr_rst <= '1'; core_rst <= '1';
      wait for 2 us;
      hr_rst <= '0'; core_rst <= '0';
      if G_PROBE_TEST then
         wait for 1 ms; probe_now <= true; wait for 1 us; done <= true; wait;
      end if;
      wait for 12 ms;
      report "after power on: picture age " & integer'image(o_age) & " frames";

      for t in 1 to G_TRIALS loop
         uniform(s1, s2, r);
         wait for r * 1.3 ms;                 -- random moment
         uniform(s1, s2, r);
         if r < 0.7 then kind := "button"; else kind := "menu  "; end if;
         core_rst <= '1';
         if kind = "button" then hr_rst <= '1'; end if;
         uniform(s1, s2, r);
         wait for 1 us + r * 100 us;
         hr_rst <= '0';
         uniform(s1, s2, r);
         wait for r * 300 us;                  -- core reset may end later
         core_rst <= '0';
         -- wait 15 output frames, then watch 5 frames
         f0 := o_frames;
         wait until o_frames = f0 + 15;
         rd0 := rd_words;
         worst := 0;
         for k in 1 to 5 loop
            wait until o_frames'event;
            if o_age > worst then worst := o_age; end if;
         end loop;
         if worst > 4 or rd_words = rd0 then
            fails := fails + 1;
            probe_now <= true;
            report "trial " & integer'image(t) & " (" & kind & "): FROZEN, picture age " &
                   integer'image(worst) & ", HyperRAM words read " & integer'image(rd_words - rd0);
         else
            report "trial " & integer'image(t) & " (" & kind & "): ok, age " & integer'image(worst);
         end if;
      end loop;
      report "RESULT: " & integer'image(fails) & " of " & integer'image(G_TRIALS) & " resets froze the picture";
      done <= true;
      wait;
   end process;

end architecture sim;
