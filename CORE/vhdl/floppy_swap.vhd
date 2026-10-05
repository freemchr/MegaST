---------------------------------------------------------------------------------------------------------
-- Atari ST/STe for MEGA65 (MegaST)
--
-- Swapping the floppy drives A: and B: (e.g. to boot from B:)
--
-- The virtual drive i (menu "Floppy A:" / "Floppy B:") is FDC drive i xor swap. The FDC (fdc1772.sv)
-- stores the geometry of an image at the rising edge of its img_mounted bit, using the one img_size
-- input. Therefore the image sizes and read-only flags are stored per virtual drive, and after a swap
-- both FDC drives are announced again, one after the other, with the stored values. The read-only
-- flags are passed per FDC drive (write protection).
--
-- Runs in the clock domain of the core.
--
-- This machine is based on AtariST_MiSTer
-- Powered by MiSTer2MEGA65
-- MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3
---------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity floppy_swap is
   port (
      clk_i            : in  std_logic;
      swap_i           : in  std_logic;

      -- virtual drives (M2M firmware): img_mounted is strobed, size and read-only are valid meanwhile
      vd_mounted_i     : in  std_logic_vector(1 downto 0);
      vd_readonly_i    : in  std_logic;
      vd_size_i        : in  std_logic_vector(31 downto 0);
      vd_sd_rd_o       : out std_logic_vector(1 downto 0);
      vd_sd_wr_o       : out std_logic_vector(1 downto 0);

      -- FDC drives
      fdc_mounted_o    : out std_logic_vector(1 downto 0);
      fdc_size_o       : out std_logic_vector(31 downto 0);
      fdc_readonly_o   : out std_logic_vector(1 downto 0);
      fdc_sd_rd_i      : in  std_logic_vector(1 downto 0);
      fdc_sd_wr_i      : in  std_logic_vector(1 downto 0)
   );
end entity floppy_swap;

architecture synthesis of floppy_swap is

   type size_array is array(0 to 1) of std_logic_vector(31 downto 0);
   signal vd_size     : size_array := (others => (others => '0'));
   signal vd_ro       : std_logic_vector(1 downto 0) := "00";
   signal swap        : std_logic := '0';                  -- the swap state the FDC knows about
   signal announce    : natural range 0 to 3 := 0;         -- 3: FDC drive 0, 2: pause, 1: FDC drive 1

begin

   state : process(clk_i)
   begin
      if rising_edge(clk_i) then
         for i in 0 to 1 loop
            if vd_mounted_i(i) = '1' then
               vd_size(i) <= vd_size_i;
               vd_ro(i)   <= vd_readonly_i;
            end if;
         end loop;

         if announce /= 0 then
            announce <= announce - 1;
         elsif swap_i /= swap then
            swap     <= swap_i;
            announce <= 3;
         end if;
      end if;
   end process state;

   mapping : process(all)
      variable v : natural range 0 to 1;
   begin
      for i in 0 to 1 loop
         v := i;
         if swap = '1' then
            v := 1 - i;
         end if;
         fdc_readonly_o(i) <= vd_ro(v);
         fdc_mounted_o(i)  <= vd_mounted_i(v);
         vd_sd_rd_o(v)     <= fdc_sd_rd_i(i);
         vd_sd_wr_o(v)     <= fdc_sd_wr_i(i);
      end loop;
      fdc_size_o <= vd_size_i;

      if announce = 3 then
         fdc_mounted_o <= "01";
         fdc_size_o    <= vd_size(0) when swap = '0' else vd_size(1);
      elsif announce = 1 then
         fdc_mounted_o <= "10";
         fdc_size_o    <= vd_size(1) when swap = '0' else vd_size(0);
      end if;
   end process mapping;

end architecture synthesis;
