-- Minimal simulation models of the Xilinx XPM CDC macros used by tos_loader.vhd (two flip-flop synchronizers)
library ieee; use ieee.std_logic_1164.all;
package vcomponents is
  component xpm_cdc_single
    generic (DEST_SYNC_FF : integer := 2; INIT_SYNC_FF : integer := 0; SIM_ASSERT_CHK : integer := 0; SRC_INPUT_REG : integer := 1);
    port (src_clk : in std_logic; src_in : in std_logic; dest_clk : in std_logic; dest_out : out std_logic);
  end component;
  component xpm_cdc_array_single
    generic (DEST_SYNC_FF : integer := 2; INIT_SYNC_FF : integer := 0; SIM_ASSERT_CHK : integer := 0; SRC_INPUT_REG : integer := 1; WIDTH : integer := 2);
    port (src_clk : in std_logic; src_in : in std_logic_vector(WIDTH-1 downto 0); dest_clk : in std_logic; dest_out : out std_logic_vector(WIDTH-1 downto 0));
  end component;
end package;
library ieee; use ieee.std_logic_1164.all;
entity xpm_cdc_single is
  generic (DEST_SYNC_FF : integer := 2; INIT_SYNC_FF : integer := 0; SIM_ASSERT_CHK : integer := 0; SRC_INPUT_REG : integer := 1);
  port (src_clk : in std_logic; src_in : in std_logic; dest_clk : in std_logic; dest_out : out std_logic);
end entity;
architecture sim of xpm_cdc_single is
  signal s : std_logic_vector(1 downto 0) := "00";
begin
  process(dest_clk) begin if rising_edge(dest_clk) then s <= s(0) & src_in; end if; end process;
  dest_out <= s(1);
end architecture;
library ieee; use ieee.std_logic_1164.all;
entity xpm_cdc_array_single is
  generic (DEST_SYNC_FF : integer := 2; INIT_SYNC_FF : integer := 0; SIM_ASSERT_CHK : integer := 0; SRC_INPUT_REG : integer := 1; WIDTH : integer := 2);
  port (src_clk : in std_logic; src_in : in std_logic_vector(WIDTH-1 downto 0); dest_clk : in std_logic; dest_out : out std_logic_vector(WIDTH-1 downto 0));
end entity;
architecture sim of xpm_cdc_array_single is
  signal s0, s1 : std_logic_vector(WIDTH-1 downto 0) := (others => '0');
begin
  process(dest_clk) begin if rising_edge(dest_clk) then s0 <= src_in; s1 <= s0; end if; end process;
  dest_out <= s1;
end architecture;
