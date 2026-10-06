-- The types of vdrives_pkg (M2M/vhdl/vdrives.vhd) without the vdrives entity and its dependencies.
library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;
package vdrives_pkg is
   type vd_vec_array is array(natural range <>) of std_logic_vector;
   type vd_std_array is array(natural range <>) of std_logic;
   type vd_unsigned_array is array(natural range <>) of unsigned;
end package;
