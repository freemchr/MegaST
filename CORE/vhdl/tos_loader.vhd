----------------------------------------------------------------------------------
-- Atari ST/STe for MEGA65
--
-- TOS and cartridge loader: QNICE devices that receive the TOS image (auto-load,
-- see C_CRTROMS_AUTO in globals.vhd) and cartridge images (manual load via the
-- on-screen-menu, see C_CRTROMS_MAN) byte by byte from the M2M ROM loader and
-- hand them over word by word to the Atari ST core, which writes them into
-- SDRAM at $E00000 (TOS) and $FA0000 (cartridge, 128 kB).
--
-- The cartridge device implements the M2M CRT/ROM control and status registers
-- (CSR) in the 4k window 0xFFFF (see CRTROM_CSR_* in M2M/rom/sysdef.asm). While
-- a cartridge is being loaded, main_cart_loading_o is high: The core is kept in
-- reset, so that the cartridge becomes active with a fresh start of the ST.
--
-- The QNICE side writes one byte per address (address = byte offset in the
-- TOS image). Two bytes form one big endian 68000 word. Every word is passed
-- to the core using a toggle handshake; while the previous word has not been
-- written to SDRAM, yet, QNICE is stalled using the wait signal.
--
-- 192k TOS images (TOS 1.00 - 1.04) are running at $FC0000 while 256k TOS
-- images (TOS 1.06 and newer) are running at $E00000. The TOS header contains
-- the base address of the ROM at offset 8 (os_beg): If the high word of it is
-- $00FC, then tos192k_o is set.
--
-- Atari ST port 2026, licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library xpm;
use xpm.vcomponents.all;

entity tos_loader is
   port (
      -- QNICE clock domain
      qnice_clk_i       : in  std_logic;
      qnice_rst_i       : in  std_logic;
      qnice_addr_i      : in  std_logic_vector(27 downto 0);
      qnice_data_i      : in  std_logic_vector(15 downto 0);
      qnice_ce_i        : in  std_logic;   -- TOS device
      qnice_cart_ce_i   : in  std_logic;   -- cartridge device
      qnice_we_i        : in  std_logic;
      qnice_wait_o      : out std_logic;
      qnice_cart_data_o : out std_logic_vector(15 downto 0);

      -- Core clock domain
      main_clk_i        : in  std_logic;
      main_dio_addr_o   : out std_logic_vector(23 downto 1);   -- 68000 word address
      main_dio_data_o   : out std_logic_vector(15 downto 0);
      main_dio_strobe_o : out std_logic;                       -- toggles for each word
      main_dio_ack_i    : in  std_logic;                       -- follows main_dio_strobe_o when done
      main_tos192k_o    : out std_logic;
      main_cart_loaded_o  : out std_logic;
      main_cart_loading_o : out std_logic
   );
end entity tos_loader;

architecture synthesis of tos_loader is

   -- TOS images are stored at $E00000 (word address $700000), maximum size is 512 kB
   constant C_TOS_BASE  : unsigned(23 downto 1) := to_unsigned(16#700000#, 23);
   -- Cartridges are stored at $FA0000 (word address $7D0000), maximum size is 128 kB
   constant C_CART_BASE : unsigned(23 downto 1) := to_unsigned(16#7D0000#, 23);

   -- M2M CRT/ROM control and status registers
   constant C_CSR_WIN      : std_logic_vector(15 downto 0) := x"FFFF";
   constant C_CSR_STATUS   : std_logic_vector(11 downto 0) := x"000";
   constant C_CSR_FS_LO    : std_logic_vector(11 downto 0) := x"001";
   constant C_CSR_FS_HI    : std_logic_vector(11 downto 0) := x"002";
   constant C_CSR_PARSEST  : std_logic_vector(11 downto 0) := x"010";
   constant C_CSR_PARSEE1  : std_logic_vector(11 downto 0) := x"011";
   constant C_ST_IDLE      : std_logic_vector(15 downto 0) := x"0000";
   constant C_ST_LOADING   : std_logic_vector(15 downto 0) := x"0001";
   constant C_ST_OK        : std_logic_vector(15 downto 0) := x"0003";
   constant C_PT_IDLE      : std_logic_vector(15 downto 0) := x"0000";
   constant C_PT_OK        : std_logic_vector(15 downto 0) := x"0002";

   signal qnice_cart_status : std_logic_vector(15 downto 0) := x"0000";
   signal qnice_cart_fs     : std_logic_vector(31 downto 0);
   signal qnice_is_csr      : std_logic;
   signal qnice_data_ce     : std_logic;
   signal qnice_base        : unsigned(23 downto 1);
   signal qnice_cart_loaded : std_logic;
   signal qnice_cart_loading: std_logic;

   signal qnice_hi_byte : std_logic_vector(7 downto 0);
   signal qnice_addr    : std_logic_vector(23 downto 1);
   signal qnice_data    : std_logic_vector(15 downto 0);
   signal qnice_tos192k : std_logic := '0';
   signal qnice_req     : std_logic := '0';
   signal qnice_ack     : std_logic;
   signal qnice_delay   : natural range 0 to 3 := 0;
   signal qnice_pending : std_logic;
   signal qnice_taken   : std_logic := '0';   -- the current write access has been captured

begin

   -- Data accesses: TOS device (all addresses) and cartridge device (except CSR window)
   qnice_is_csr  <= '1' when qnice_addr_i(27 downto 12) = C_CSR_WIN else '0';
   qnice_data_ce <= qnice_ce_i or (qnice_cart_ce_i and not qnice_is_csr);
   qnice_base    <= C_CART_BASE when qnice_cart_ce_i = '1' else C_TOS_BASE;

   -- A new word can only be accepted when the previous word has been written.
   -- The QNICE CPU samples wait at its rising clock edge, while this device captures the
   -- word at the falling edge before: Once the word of the current write access has been
   -- captured (qnice_taken), wait must stay low, otherwise the CPU would repeat the access
   -- forever (each capture makes qnice_pending high again).
   qnice_pending <= '1' when qnice_req /= qnice_ack or qnice_delay /= 0 else '0';
   qnice_wait_o  <= qnice_data_ce and qnice_we_i and qnice_addr_i(0) and qnice_pending and not qnice_taken;

   -- Cartridge CSR read access
   cart_read : process(all)
   begin
      qnice_cart_data_o <= x"0000";
      if qnice_is_csr = '1' then
         case qnice_addr_i(11 downto 0) is
            when C_CSR_STATUS  => qnice_cart_data_o <= qnice_cart_status;
            when C_CSR_FS_LO   => qnice_cart_data_o <= qnice_cart_fs(15 downto 0);
            when C_CSR_FS_HI   => qnice_cart_data_o <= qnice_cart_fs(31 downto 16);
            when C_CSR_PARSEST =>
               -- there is nothing to parse: a raw cartridge image is ready as soon as it is loaded
               if qnice_cart_status = C_ST_OK then
                  qnice_cart_data_o <= C_PT_OK;
               else
                  qnice_cart_data_o <= C_PT_IDLE;
               end if;
            when others        => qnice_cart_data_o <= x"0000";   -- error code and error string
         end case;
      end if;
   end process cart_read;

   qnice_cart_loaded  <= '1' when qnice_cart_status = C_ST_OK      else '0';
   qnice_cart_loading <= '1' when qnice_cart_status = C_ST_LOADING else '0';

   qnice_proc : process(qnice_clk_i)
   begin
      if falling_edge(qnice_clk_i) then
         -- The data needs to be stable in the core clock domain before the request toggles:
         -- Toggle the request three QNICE clock cycles after the data has been updated.
         if qnice_delay /= 0 then
            qnice_delay <= qnice_delay - 1;
            if qnice_delay = 1 then
               qnice_req <= not qnice_req;
            end if;
         end if;

         -- Cartridge CSR write access
         if qnice_cart_ce_i = '1' and qnice_we_i = '1' and qnice_is_csr = '1' then
            case qnice_addr_i(11 downto 0) is
               when C_CSR_STATUS => qnice_cart_status              <= qnice_data_i;
               when C_CSR_FS_LO  => qnice_cart_fs(15 downto 0)     <= qnice_data_i;
               when C_CSR_FS_HI  => qnice_cart_fs(31 downto 16)    <= qnice_data_i;
               when others       => null;
            end case;
         end if;

         if qnice_data_ce = '1' and qnice_we_i = '1' then
            if qnice_addr_i(0) = '0' then
               qnice_hi_byte <= qnice_data_i(7 downto 0);
            elsif qnice_pending = '0' and qnice_taken = '0' then
               qnice_taken <= '1';
               qnice_data  <= qnice_hi_byte & qnice_data_i(7 downto 0);
               qnice_addr  <= std_logic_vector(qnice_base + unsigned(qnice_addr_i(18 downto 1)));
               qnice_delay <= 3;

               -- TOS header: os_beg at offset 8
               if qnice_ce_i = '1' and unsigned(qnice_addr_i) = 9 then
                  if qnice_hi_byte = x"00" and qnice_data_i(7 downto 0) = x"FC" then
                     qnice_tos192k <= '1';
                  else
                     qnice_tos192k <= '0';
                  end if;
               end if;
            end if;
         end if;

         -- the write access ends as soon as the CPU continues with the next instruction
         if qnice_data_ce = '0' or qnice_we_i = '0' then
            qnice_taken <= '0';
         end if;

         if qnice_rst_i = '1' then
            qnice_taken       <= '0';
            qnice_req         <= '0';
            qnice_delay       <= 0;
            qnice_tos192k     <= '0';
            qnice_cart_status <= C_ST_IDLE;
         end if;
      end if;
   end process qnice_proc;

   ---------------------------------------------------------------------------------------------
   -- Clock domain crossing
   ---------------------------------------------------------------------------------------------

   i_cdc_q2m_data : xpm_cdc_array_single
      generic map (
         DEST_SYNC_FF   => 2,
         INIT_SYNC_FF   => 0,
         SIM_ASSERT_CHK => 0,
         SRC_INPUT_REG  => 0,
         WIDTH          => 42
      )
      port map (
         src_clk               => qnice_clk_i,
         src_in(22 downto 0)   => qnice_addr,
         src_in(38 downto 23)  => qnice_data,
         src_in(39)            => qnice_tos192k,
         src_in(40)            => qnice_cart_loaded,
         src_in(41)            => qnice_cart_loading,
         dest_clk              => main_clk_i,
         dest_out(22 downto 0) => main_dio_addr_o,
         dest_out(38 downto 23)=> main_dio_data_o,
         dest_out(39)          => main_tos192k_o,
         dest_out(40)          => main_cart_loaded_o,
         dest_out(41)          => main_cart_loading_o
      ); -- i_cdc_q2m_data

   i_cdc_q2m_req : xpm_cdc_single
      generic map (
         DEST_SYNC_FF   => 2,
         INIT_SYNC_FF   => 0,
         SIM_ASSERT_CHK => 0,
         SRC_INPUT_REG  => 0
      )
      port map (
         src_clk  => qnice_clk_i,
         src_in   => qnice_req,
         dest_clk => main_clk_i,
         dest_out => main_dio_strobe_o
      ); -- i_cdc_q2m_req

   i_cdc_m2q_ack : xpm_cdc_single
      generic map (
         DEST_SYNC_FF   => 2,
         INIT_SYNC_FF   => 0,
         SIM_ASSERT_CHK => 0,
         SRC_INPUT_REG  => 0
      )
      port map (
         src_clk  => main_clk_i,
         src_in   => main_dio_ack_i,
         dest_clk => qnice_clk_i,
         dest_out => qnice_ack
      ); -- i_cdc_m2q_ack

end architecture synthesis;

