# read the MegaST JTAG probe (USER1) N times, print one hex word per line
set n [expr {[info exists ::env(N)] ? $::env(N) : 400}]
open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target -jtag_mode on
for {set i 0} {$i < $n} {incr i} {
  scan_ir_hw_jtag 6 -tdi 02
  puts "S [scan_dr_hw_jtag 64 -tdi 0000000000000000]"
}
close_hw_target
