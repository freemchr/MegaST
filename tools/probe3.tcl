# Sample the keyboard probe (USER3, 176 bits, see CORE/vhdl/mega65.vhd) $N times, every 250 ms
set n [expr {[info exists ::env(N)] ? $::env(N) : 20}]
open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target -jtag_mode on
for {set i 0} {$i < $n} {incr i} {
  scan_ir_hw_jtag 6 -tdi 22
  puts "K [scan_dr_hw_jtag 176 -tdi 00000000000000000000000000000000000000000000]"
  after 250
}
close_hw_target
