# Written by Claude.
# Program the connected Basys 3 over JTAG (volatile; lost on power cycle).
#   vivado -mode batch -source fpga/program.tcl [-tclargs path/to/file.bit]

set bit [file join [file dirname [file normalize [info script]]] build basys3_top.bit]
if {[llength $argv] > 0} { set bit [file normalize [lindex $argv 0]] }

open_hw_manager
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices xc7a35t*] 0]
current_hw_device $dev
set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
close_hw_manager
