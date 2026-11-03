set root [file normalize [file join [file dirname [info script]] ../..]]
set sim_dir [file join $root tmp modelsim_awb_calibrated_refs]
set is_batch [batch_mode]
onerror {if {[batch_mode]} {quit -force -code 1} else {abort}}
quit -sim
file mkdir $sim_dir
cd $sim_dir
vmap -c
if {![file isdirectory work]} {vlib work}
vmap work [file join $sim_dir work]
vlog -work work [file join $root src rtl isp frame_awb.v]
vlog -work work [file join $root src sim tb_awb_calibrated_refs.v]
vsim -voptargs=+acc work.tb_awb_calibrated_refs
onfinish stop
run 3 ms
set finished [examine -radix unsigned sim:/tb_awb_calibrated_refs/test_done]
set errors [examine -radix decimal sim:/tb_awb_calibrated_refs/errors]
if {$finished != 1 || $errors != 0} {if {$is_batch} {quit -force -code 1}; error "calibrated AWB references failed or timed out"}
if {$is_batch} {quit -force -code 0}
