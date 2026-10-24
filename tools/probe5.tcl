# Falcon CPU/DSP state (USER2 bits 255..96, CORE/vhdl/mega65.vhd), $N samples $MS ms apart
set n  [expr {[info exists ::env(N)]  ? $::env(N)  : 20}]
set ms [expr {[info exists ::env(MS)] ? $::env(MS) : 100}]
open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target -jtag_mode on
for {set i 0} {$i < $n} {incr i} {
  scan_ir_hw_jtag 6 -tdi 03
  puts "F [scan_dr_hw_jtag 256 -tdi [string repeat 0 64]]"
  after $ms
}
close_hw_target
