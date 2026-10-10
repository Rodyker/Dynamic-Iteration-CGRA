# Written by Claude.
# Non-project Vivado build for the Basys 3. Bakes a config into the bitstream.
#   vivado -mode batch -source fpga/build.tcl -tclargs [config.bin [sw_slot led_out inputs_hex [name]]]
# inputs_hex is input[3]..input[0] as 16 hex digits. Outputs go to fpga/build/<name>.*
# (Arguments are positional because vivado.bat splits arguments at '='.)

set here [file dirname [file normalize [info script]]]
set root [file dirname $here]
set out  [file join $here build]
file mkdir $out

set cfg_path [file join $root config.bin]
if {[llength $argv] > 0} { set cfg_path [file normalize [lindex $argv 0]] }
set name basys3_top
if {[llength $argv] > 4} { set name [lindex $argv 4] }

set f [open $cfg_path rb]
set data [read $f]
close $f
binary scan $data cu* bytes
if {[llength $bytes] != 33} { error "$cfg_path: expected 33 bytes, got [llength $bytes]" }
set hex ""
foreach b [lreverse $bytes] { append hex [format %02x $b] }
puts "Config $cfg_path = 264'h$hex"

set generics [list -generic "CONFIG=264'h$hex"]
if {[llength $argv] > 3} {
    lappend generics -generic "SW_SLOT=[lindex $argv 1]" \
                     -generic "LED_OUT=[lindex $argv 2]" \
                     -generic "INPUTS=64'h[lindex $argv 3]"
}

read_verilog -sv [list \
    [file join $root cgra_pkg.sv] \
    [file join $root pe.sv] \
    [file join $root lcu.sv] \
    [file join $root top.sv] \
    [file join $here basys3_top.sv]]
read_xdc [file join $here basys3.xdc]

synth_design -top basys3_top -part xc7a35tcpg236-1 {*}$generics
opt_design
place_design
route_design

report_utilization    -file [file join $out ${name}_utilization.rpt]
report_timing_summary -file [file join $out ${name}_timing.rpt]
puts "CGRA_WNS [get_property SLACK [get_timing_paths -max_paths 1 -setup]]"
write_bitstream -force [file join $out ${name}.bit]
