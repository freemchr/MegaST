open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target
set d [lindex [get_hw_devices xc7a200t_0] 0]
current_hw_device $d
# bitstream: $BIT or the last build of the R6 project
set bit [expr {[info exists ::env(BIT)] ? $::env(BIT) : "[file dirname [info script]]/../CORE/CORE-R6.runs/impl_1/mega65_r6.bit"}]
set_property PROGRAM.FILE $bit $d
program_hw_devices $d
refresh_hw_device -update_hw_probes false $d
puts "DONE=[get_property REGISTER.CONFIG_STATUS.BIT14_DONE_PIN $d]"
close_hw_target
disconnect_hw_server
