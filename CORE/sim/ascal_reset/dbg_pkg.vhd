-- Issue #26 bench: the testbench sets probe_now when a reset froze the picture; the simulation copies of
-- ascal, avm_arbit and avm_decrease (made by probes.py) then print their state.
package dbg_pkg is
   signal probe_now : boolean := false;
end package dbg_pkg;
