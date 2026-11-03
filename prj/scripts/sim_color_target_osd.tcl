set root [file normalize [file join [file dirname [info script]] ../..]]
set sim_dir [file join $root tmp modelsim_color_target_osd]
onerror {quit -force -code 1}
quit -sim
file mkdir $sim_dir
cd $sim_dir
transcript file [file join $sim_dir transcript.log]
vmap -c
if {![file isdirectory work]} {vlib work}
vmap work [file join $sim_dir work]
vlog -work work [file join $root prj td lab_ex3_sc520 user_source hdl_source osd_char_lib.v] [file join $root src rtl osd color_target_osd.v] [file join $root src sim tb_color_target_osd.v]
vsim -voptargs=+acc work.tb_color_target_osd
onfinish stop
run 2 ms
if {[examine -radix unsigned sim:/tb_color_target_osd/test_done]!=1 || [examine -radix decimal sim:/tb_color_target_osd/errors]!=0} {quit -force -code 1}
quit -force -code 0
