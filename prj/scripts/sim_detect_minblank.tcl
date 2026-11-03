set root [file normalize [file join [file dirname [info script]] ../..]]
set sim_dir [file join $root tmp modelsim_detect_minblank]
set is_batch [batch_mode]
onerror {if {[batch_mode]} {quit -force -code 1} else {abort}}
quit -sim
file mkdir $sim_dir
cd $sim_dir
transcript file [file join $sim_dir transcript.log]
vmap -c
if {![file isdirectory work]} {vlib work}
vmap work [file join $sim_dir work]
source [file join $root prj scripts sim_eram_model.tcl]
if {[catch {vlog -work work [file join $root src rtl detect detect_shape.v] [file join $root src sim tb_detect_minblank.v]} failure]} {if {$is_batch} {quit -force -code 1};error $failure}
eval vsim -voptargs=+acc work.tb_detect_minblank $eram_sim_top
onfinish stop
run 100 us
if {[examine -radix unsigned sim:/tb_detect_minblank/test_done]!=1 || [examine -radix unsigned sim:/tb_detect_minblank/errors]!=0} {if {$is_batch} {quit -force -code 1};error "field failed"}
if {$is_batch} {quit -force -code 0}
