set n [expr {[info exists ::env(N)] ? $::env(N) : 20}]
open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target -jtag_mode on
for {set i 0} {$i < $n} {incr i} {
  scan_ir_hw_jtag 6 -tdi 03
  puts "J [scan_dr_hw_jtag 96 -tdi 000000000000000000000000]"
  after 250
}
close_hw_target
