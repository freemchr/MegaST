-- Issue #38: the Falcon's interlaced modes on HDMI. ascal (as in digital_pipeline.vhd: triple buffer,
-- INTER => true) gets fields like the Videl's: one field shows the odd rows of the picture, the next
-- the even rows (60 of 120 each), with i_fl as falcon_videl.sv's ilace_fl (1 = odd rows). The pixels code
-- their source row in green. The frame buffer is 24 bpp here: with 16 bpp (the core's format) this bench
-- reads wrong colours even for progressive video, which works on the hardware (the 16-bit memory model
-- does not match the HyperRAM path's byte order); the weave only changes the line addresses. ascal must weave the fields:
-- output line n (1:1, 120 lines) shows row n. G_ILACE = false: the same 120 rows progressive, i_fl = 0.
--
-- MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity tb_ascal_ilace is
   generic (
      G_ILACE  : boolean := true;
      G_FRAMES : natural := 12          -- output frames checked
   );
end entity tb_ascal_ilace;

architecture sim of tb_ascal_ilace is

   -- input video (Falcon side): 160x120 picture, 25 MHz; interlaced: fields of 60 lines (68 in total)
   constant I_HT : natural := 200; constant I_HA : natural := 160;
   function sel(c : boolean; a, b : natural) return natural is
   begin if c then return a; else return b; end if; end function;
   constant I_VT : natural := sel(G_ILACE, 68, 135); constant I_VA : natural := sel(G_ILACE, 60, 120);
   constant I_VS0 : natural := sel(G_ILACE, 63, 125); constant I_VS1 : natural := sel(G_ILACE, 65, 127);
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
   signal field  : std_logic := '0';   -- as falcon_videl.sv: toggles at the start of each field
   signal i_fl   : std_logic;
   signal i_row  : natural;

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
   signal o_frames    : natural := 0;
   signal o_bad       : natural := 0;    -- lines of the last output frame that show the wrong row
   signal o_lines     : natural := 0;    -- lines of the last output frame
   signal o_first_bad : integer := -1;
   signal o_first_got : integer := -1;
   signal o_seq       : string(1 to 64) := (others => ' ');   -- rows of output lines 0..7 and 112..119

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
                  field <= not field;
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
   -- field 1 fetches the odd rows (falcon_videl.sv: base + stride)
   i_row <= 2 * i_vc + 1 when G_ILACE and field = '1' else 2 * i_vc when G_ILACE else i_vc;
   i_fl  <= field when G_ILACE else '0';   -- falcon_videl.sv ilace_fl
   i_r   <= x"00";
   i_g   <= to_unsigned(i_row, 8);
   i_b   <= x"00";

   ---------------------------------------------------------------------------
   i_ascal : entity work.ascal
      generic map (
         MASK => x"f1", RAMBASE => (others => '0'), RAMSIZE => to_unsigned(524288, 32),   -- 3 buffers of 160x120 at 16 bpp
         INTER => true, HEADER => false, DOWNSCALE => true, DOWNSCALE_NN => true,
         BYTESWAP => true, ADAPTIVE => true, PALETTE => false, PALETTE2 => false,
         FRAC => 6, OHRES => 2048, IHRES => 1024, N_DW => 128, N_AW => 19, N_BURST => 128
      )
      port map (
         i_r => i_r, i_g => i_g, i_b => i_b, i_hs => i_hs, i_vs => i_vs, i_fl => i_fl,
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
         run => '1', freeze => '0', mode => "01000",   -- nearest neighbour, triple buffer
         htotal => 200, hsstart => 168, hsend => 184, hdisp => 160, hmin => 0, hmax => 159,
         vtotal => 130, vsstart => 122, vsend => 124, vdisp => 120, vmin => 0, vmax => 119,
         format => "01",   -- 24 bpp, see the header
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
                  if m_be(1) = '1' then mem(adr)(15 downto 8) := m_wdata(15 downto 8); end if;
                  if m_be(0) = '1' then mem(adr)(7 downto 0) := m_wdata(7 downto 0); end if;
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
                  if m_be(1) = '1' then mem(adr)(15 downto 8) := m_wdata(15 downto 8); end if;
                  if m_be(0) = '1' then mem(adr)(7 downto 0) := m_wdata(7 downto 0); end if;
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
   -- Monitor: the source row of the pixel in the middle of every output line
   ---------------------------------------------------------------------------
   p_mon : process (o_clk)
      variable ln, px, bad : natural := 0;
      variable fb, fg : integer := -1;
      variable vs_d, de_d : std_logic := '0';
      variable got : natural;
      variable seq : string(1 to 64) := (others => ' ');
      variable sp  : natural := 1;
   begin
      if rising_edge(o_clk) then
         if o_vs = '1' and vs_d = '0' then
            o_bad <= bad; o_lines <= ln; o_first_bad <= fb; o_first_got <= fg; o_seq <= seq;
            ln := 0; bad := 0; fb := -1; fg := -1; seq := (others => ' '); sp := 1;
            o_frames <= o_frames + 1;
         end if;
         if o_de = '1' then
            if de_d = '0' then px := 0; ln := ln + 1; else px := px + 1; end if;
            if px = 80 then
               got := to_integer(o_g);
               if (ln <= 8 or ln > 112) and sp + 4 <= 64 then
                  seq(sp to sp + 2) := integer'image(got + 1000)(2 to 4); seq(sp + 3) := ' '; sp := sp + 4;
               end if;
               if got /= ln - 1 then
                  bad := bad + 1;
                  if fb < 0 then fb := ln - 1; fg := got; end if;
               end if;
            end if;
         end if;
         vs_d := o_vs; de_d := o_de;
      end if;
   end process;

   ---------------------------------------------------------------------------
   p_main : process
      variable fails : natural := 0;
   begin
      hr_rst <= '1'; core_rst <= '1';
      wait for 2 us;
      hr_rst <= '0'; core_rst <= '0';
      wait until o_frames = 20;               -- interlace detected, buffers filled
      for k in 1 to G_FRAMES loop
         wait until o_frames'event;
         if o_bad /= 0 or o_lines /= 120 then
            fails := fails + 1;
            report "frame " & integer'image(k) & ": " & integer'image(o_lines) & " lines, " &
                   integer'image(o_bad) & " wrong, first: line " & integer'image(o_first_bad) &
                   " shows row " & integer'image(o_first_got) & ", rows of lines 0-7, 112-119: " & o_seq;
         end if;
      end loop;
      if fails = 0 then
         report "RESULT: OK, " & integer'image(G_FRAMES) & " output frames of 120 lines, every line its own row";
      else
         report "RESULT: FAIL, " & integer'image(fails) & " of " & integer'image(G_FRAMES) & " frames wrong";
      end if;
      done <= true;
      wait;
   end process;

end architecture sim;
