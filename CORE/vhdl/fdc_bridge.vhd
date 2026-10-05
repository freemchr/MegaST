----------------------------------------------------------------------------------
-- Atari ST/STe for MEGA65 (MegaST)
--
-- Bridge between the M2M virtual drives (vdrives.vhd, QNICE clock domain,
-- 8-bit "SD byte level access") and the Atari ST floppy controller
-- (fdc1772.sv) and ACSI hard disk controller (acsi_ctrl.sv), which are using
-- the core clock domain and the 16-bit "WIDE" MiSTer SD interface.
--
-- Each drive has its own LBA, read/write requests and acknowledge signal. The
-- sector buffer interface (address, data, write strobe) is shared: A client
-- must only use it while its acknowledge signal is high.
--
-- QNICE -> core (reading sectors):
--    QNICE writes the sector byte by byte into the core's sector buffer. The
--    M2M firmware does not reliably toggle sd_buff_wr between two bytes (MiSTer
--    cores use it as a level sensitive write enable), therefore the strobe
--    qnice_buff_wr_i must be generated for each QNICE write access to the
--    sd_buff_wr register (see mega65.vhd). Two
--    consecutive bytes (even, odd) are combined into one 16-bit word (little
--    endian, like MiSTer's hps_io in WIDE mode) and are handed over to the core
--    clock domain using a toggle handshake. The acknowledge signal towards the
--    core stays high until the last word has been written, so that the FDC never
--    sees the end of the transfer before all data has arrived.
--
-- core -> QNICE (writing sectors):
--    QNICE sets sd_buff_addr and reads sd_buff_din. The address is transferred
--    to the core clock domain and the byte is transferred back. This takes a
--    few hundred nanoseconds, so mega65.vhd stalls QNICE using wait states when
--    it reads sd_buff_din (C_VD_DIN_WAIT).
--
-- This machine is based on AtariST_MiSTer
-- Powered by MiSTer2MEGA65
-- MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.vdrives_pkg.all;

library xpm;
use xpm.vcomponents.all;

entity fdc_bridge is
   generic (
      G_VDNUM           : natural
   );
   port (
      -- QNICE clock domain: connect to vdrives.vhd
      qnice_clk_i       : in  std_logic;
      qnice_rst_i       : in  std_logic;
      qnice_sd_lba_o    : out vd_vec_array(G_VDNUM - 1 downto 0)(31 downto 0);
      qnice_sd_rd_o     : out vd_std_array(G_VDNUM - 1 downto 0);
      qnice_sd_wr_o     : out vd_std_array(G_VDNUM - 1 downto 0);
      qnice_sd_ack_i    : in  vd_std_array(G_VDNUM - 1 downto 0);
      qnice_buff_addr_i : in  std_logic_vector(13 downto 0);
      qnice_buff_dout_i : in  std_logic_vector(7 downto 0);
      qnice_buff_din_o  : out vd_vec_array(G_VDNUM - 1 downto 0)(7 downto 0);
      qnice_buff_wr_i   : in  std_logic;   -- high while QNICE writes '1' to sd_buff_wr

      -- Core clock domain: connect to fdc1772.sv
      main_clk_i        : in  std_logic;
      main_sd_lba_i     : in  std_logic_vector(32 * G_VDNUM - 1 downto 0);   -- drive i: bits 32*i+31 .. 32*i
      main_sd_rd_i      : in  std_logic_vector(G_VDNUM - 1 downto 0);
      main_sd_wr_i      : in  std_logic_vector(G_VDNUM - 1 downto 0);
      main_sd_ack_o     : out std_logic_vector(G_VDNUM - 1 downto 0);
      main_buff_addr_o  : out std_logic_vector(7 downto 0);
      main_buff_dout_o  : out std_logic_vector(15 downto 0);
      main_buff_din_i   : in  std_logic_vector(16 * G_VDNUM - 1 downto 0);   -- drive i: bits 16*i+15 .. 16*i
      main_buff_wr_o    : out std_logic
   );
end entity fdc_bridge;

architecture synthesis of fdc_bridge is

   -- QNICE clock domain
   signal qnice_wr_d       : std_logic := '0';
   signal qnice_lo_byte    : std_logic_vector(7 downto 0);
   signal qnice_w_addr     : std_logic_vector(7 downto 0);
   signal qnice_w_data     : std_logic_vector(15 downto 0);
   signal qnice_w_req      : std_logic := '0';
   signal qnice_w_ack      : std_logic;
   signal qnice_w_delay    : natural range 0 to 3 := 0;
   signal qnice_pending    : std_logic;
   signal qnice_ack_core   : std_logic_vector(G_VDNUM - 1 downto 0);
   signal qnice_active     : natural range 0 to G_VDNUM - 1 := 0;   -- drive of the current transfer
   signal qnice_rd_byte    : std_logic_vector(7 downto 0);
   signal qnice_lba        : std_logic_vector(32 * G_VDNUM - 1 downto 0);
   signal qnice_rd         : std_logic_vector(G_VDNUM - 1 downto 0);
   signal qnice_wr         : std_logic_vector(G_VDNUM - 1 downto 0);

   -- Core clock domain
   signal main_w_req       : std_logic;
   signal main_w_req_d     : std_logic := '0';
   signal main_w_addr      : std_logic_vector(7 downto 0);
   signal main_w_data      : std_logic_vector(15 downto 0);
   signal main_w_strobe    : std_logic;
   signal main_rd_addr     : std_logic_vector(8 downto 0);
   signal main_rd_byte     : std_logic_vector(7 downto 0);
   signal main_ack         : std_logic_vector(G_VDNUM - 1 downto 0);
   signal main_din         : std_logic_vector(15 downto 0);

   -- core to QNICE clock domain crossing: read byte, lba, read and write requests
   constant C_M2Q_WIDTH    : natural := 8 + 34 * G_VDNUM;
   signal m2q_src          : std_logic_vector(C_M2Q_WIDTH - 1 downto 0);
   signal m2q_dst          : std_logic_vector(C_M2Q_WIDTH - 1 downto 0);

begin

   ---------------------------------------------------------------------------------------------
   -- QNICE clock domain
   ---------------------------------------------------------------------------------------------

   qnice_pending  <= '1' when qnice_w_req /= qnice_w_ack or qnice_w_delay /= 0 else '0';

   -- remember the drive of the current transfer and keep its acknowledge high until
   -- the core has received the last word
   active_proc : process(qnice_clk_i)
   begin
      if rising_edge(qnice_clk_i) then
         for i in 0 to G_VDNUM - 1 loop
            if qnice_sd_ack_i(i) = '1' then
               qnice_active <= i;
            end if;
         end loop;
      end if;
   end process active_proc;

   ack_core : process(all)
   begin
      for i in 0 to G_VDNUM - 1 loop
         if qnice_sd_ack_i(i) = '1' or (qnice_pending = '1' and qnice_active = i) then
            qnice_ack_core(i) <= '1';
         else
            qnice_ack_core(i) <= '0';
         end if;
      end loop;
   end process ack_core;

   qnice_write_proc : process(qnice_clk_i)
   begin
      if rising_edge(qnice_clk_i) then
         qnice_wr_d <= qnice_buff_wr_i;

         -- the data needs to be stable in the core clock domain before the request toggles
         if qnice_w_delay /= 0 then
            qnice_w_delay <= qnice_w_delay - 1;
            if qnice_w_delay = 1 then
               qnice_w_req <= not qnice_w_req;
            end if;
         end if;

         -- rising edge of the write strobe
         if qnice_buff_wr_i = '1' and qnice_wr_d = '0' then
            if qnice_buff_addr_i(0) = '0' then
               qnice_lo_byte <= qnice_buff_dout_i;
            else
               qnice_w_data  <= qnice_buff_dout_i & qnice_lo_byte;
               qnice_w_addr  <= qnice_buff_addr_i(8 downto 1);
               qnice_w_delay <= 3;
            end if;
         end if;

         if qnice_rst_i = '1' then
            qnice_w_req   <= '0';
            qnice_w_delay <= 0;
         end if;
      end if;
   end process qnice_write_proc;

   qnice_outputs : for i in 0 to G_VDNUM - 1 generate
      qnice_sd_lba_o(i)   <= qnice_lba(32 * i + 31 downto 32 * i);
      qnice_sd_rd_o(i)    <= qnice_rd(i);
      qnice_sd_wr_o(i)    <= qnice_wr(i);
      qnice_buff_din_o(i) <= qnice_rd_byte;
   end generate qnice_outputs;

   ---------------------------------------------------------------------------------------------
   -- Core clock domain
   ---------------------------------------------------------------------------------------------

   main_w_strobe    <= main_w_req xor main_w_req_d;
   main_buff_wr_o   <= main_w_strobe;
   main_buff_addr_o <= main_w_addr when main_w_strobe = '1' else main_rd_addr(8 downto 1);
   main_buff_dout_o <= main_w_data;
   main_sd_ack_o    <= main_ack;

   -- read data: sector buffer of the drive that is currently acknowledged
   din_mux : process(all)
   begin
      main_din <= main_buff_din_i(15 downto 0);
      for i in 0 to G_VDNUM - 1 loop
         if main_ack(i) = '1' then
            main_din <= main_buff_din_i(16 * i + 15 downto 16 * i);
         end if;
      end loop;
   end process din_mux;

   main_proc : process(main_clk_i)
   begin
      if rising_edge(main_clk_i) then
         main_w_req_d <= main_w_req;

         -- the sector buffers of the clients have a registered output
         if main_rd_addr(0) = '0' then
            main_rd_byte <= main_din(7 downto 0);
         else
            main_rd_byte <= main_din(15 downto 8);
         end if;
      end if;
   end process main_proc;

   ---------------------------------------------------------------------------------------------
   -- Clock domain crossing
   ---------------------------------------------------------------------------------------------

   -- QNICE to core: write data, write address and read address (stable when used)
   i_cdc_q2m_data : xpm_cdc_array_single
      generic map (
         DEST_SYNC_FF   => 2,
         INIT_SYNC_FF   => 0,
         SIM_ASSERT_CHK => 0,
         SRC_INPUT_REG  => 1,
         WIDTH          => 33
      )
      port map (
         src_clk                => qnice_clk_i,
         src_in(15 downto 0)    => qnice_w_data,
         src_in(23 downto 16)   => qnice_w_addr,
         src_in(32 downto 24)   => qnice_buff_addr_i(8 downto 0),
         dest_clk               => main_clk_i,
         dest_out(15 downto 0)  => main_w_data,
         dest_out(23 downto 16) => main_w_addr,
         dest_out(32 downto 24) => main_rd_addr
      ); -- i_cdc_q2m_data

   i_cdc_q2m_req : xpm_cdc_single
      generic map (
         DEST_SYNC_FF   => 2,
         INIT_SYNC_FF   => 0,
         SIM_ASSERT_CHK => 0,
         SRC_INPUT_REG  => 1
      )
      port map (
         src_clk  => qnice_clk_i,
         src_in   => qnice_w_req,
         dest_clk => main_clk_i,
         dest_out => main_w_req
      ); -- i_cdc_q2m_req

   i_cdc_q2m_ack : xpm_cdc_array_single
      generic map (
         DEST_SYNC_FF   => 2,
         INIT_SYNC_FF   => 0,
         SIM_ASSERT_CHK => 0,
         SRC_INPUT_REG  => 1,
         WIDTH          => G_VDNUM
      )
      port map (
         src_clk  => qnice_clk_i,
         src_in   => qnice_ack_core,
         dest_clk => main_clk_i,
         dest_out => main_ack
      ); -- i_cdc_q2m_ack

   -- core to QNICE: handshake for the written words, read data, lba, read and write requests
   i_cdc_m2q_wack : xpm_cdc_single
      generic map (
         DEST_SYNC_FF   => 2,
         INIT_SYNC_FF   => 0,
         SIM_ASSERT_CHK => 0,
         SRC_INPUT_REG  => 1
      )
      port map (
         src_clk  => main_clk_i,
         src_in   => main_w_req_d,
         dest_clk => qnice_clk_i,
         dest_out => qnice_w_ack
      ); -- i_cdc_m2q_wack

   m2q_src(7 downto 0)                                           <= main_rd_byte;
   m2q_src(8 + 32 * G_VDNUM - 1 downto 8)                        <= main_sd_lba_i;
   m2q_src(8 + 33 * G_VDNUM - 1 downto 8 + 32 * G_VDNUM)         <= main_sd_rd_i;
   m2q_src(8 + 34 * G_VDNUM - 1 downto 8 + 33 * G_VDNUM)         <= main_sd_wr_i;
   qnice_rd_byte                                                 <= m2q_dst(7 downto 0);
   qnice_lba                                                     <= m2q_dst(8 + 32 * G_VDNUM - 1 downto 8);
   qnice_rd                                                      <= m2q_dst(8 + 33 * G_VDNUM - 1 downto 8 + 32 * G_VDNUM);
   qnice_wr                                                      <= m2q_dst(8 + 34 * G_VDNUM - 1 downto 8 + 33 * G_VDNUM);

   i_cdc_m2q_data : xpm_cdc_array_single
      generic map (
         DEST_SYNC_FF   => 2,
         INIT_SYNC_FF   => 0,
         SIM_ASSERT_CHK => 0,
         SRC_INPUT_REG  => 1,
         WIDTH          => C_M2Q_WIDTH
      )
      port map (
         src_clk        => main_clk_i,
         src_in         => m2q_src,
         dest_clk       => qnice_clk_i,
         dest_out       => m2q_dst
      ); -- i_cdc_m2q_data

end architecture synthesis;

