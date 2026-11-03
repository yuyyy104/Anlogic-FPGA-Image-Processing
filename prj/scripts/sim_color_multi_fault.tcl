set root [file normalize [file join [file dirname [info script]] ../..]]
set sim_dir [file join $root tmp modelsim_color_multitarget]
onerror {quit -force -code 1}
quit -sim
file mkdir $sim_dir
cd $sim_dir
transcript file [file join $sim_dir transcript.log]
vmap -c
if {![file isdirectory work]} {vlib work}
vmap work [file join $sim_dir work]
source [file join $root prj scripts sim_eram_model.tcl]
if {[catch {
vlog -work work [file join $root src rtl detect color_component.v] [file join $root src rtl detect color_scan_runs.v] [file join $root src rtl detect shape_labels.v] [file join $root src rtl detect shape_polygon.v] [file join $root src rtl detect color_multitarget.v]
vlog -work work [file join $root src sim tb_color_multi_fault.v]
vsim -voptargs=+acc work.tb_color_multi_fault $eram_sim_top
} failure]} {puts "COMPILE_FAILED $failure";quit -force -code 1}
onfinish stop
run 100 ms
if {[examine -radix unsigned sim:/tb_color_multi_fault/test_done]!=1 || [examine -radix decimal sim:/tb_color_multi_fault/errors]!=0} {quit -force -code 1}
quit -force -code 0
