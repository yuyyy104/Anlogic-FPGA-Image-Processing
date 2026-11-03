set root [file normalize [file join [file dirname [info script]] ../..]]
if {![info exists quality_sim_dir]} {set quality_sim_dir [file join $root tmp modelsim_shared_denoise]}
set is_batch [batch_mode]
onerror {if {[batch_mode]} {quit -force -code 1} else {abort}}
proc checked_vlog {args} {
    if {[catch {eval vlog $args} failure]} {puts stderr $failure; quit -force -code 1}
}
quit -sim
file mkdir $quality_sim_dir
cd $quality_sim_dir
transcript file [file join $quality_sim_dir transcript.log]
vmap -c
if {![file isdirectory work]} {vlib work}
vmap work [file join $quality_sim_dir work]
source [file join $root prj scripts sim_eram_model.tcl]
checked_vlog -work work [file join $root src rtl preproc shared_denoise.v]
checked_vlog -work work [file join $root src sim tb_shared_denoise.v]
if {![info exists quality_args]} {set quality_args {}}
eval vsim -voptargs=+acc $quality_args work.tb_shared_denoise $eram_sim_top
onfinish stop
run 80 ms
set done [examine -radix unsigned sim:/tb_shared_denoise/test_done]
set errors [examine -radix decimal sim:/tb_shared_denoise/errors]
if {$done!=1 || $errors!=0} {quit -force -code 1}
if {$is_batch} {quit -force -code 0}
