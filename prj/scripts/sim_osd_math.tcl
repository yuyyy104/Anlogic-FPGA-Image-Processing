set root [file normalize [file join [file dirname [info script]] ../..]]
set dir [file join $root tmp modelsim_osd_math]
set is_batch [batch_mode]
onerror {quit -force -code 1}
quit -sim
file mkdir $dir
cd $dir
transcript file [file join $dir transcript.log]
vmap -c
if {![file isdirectory work]} {vlib work}
vmap work [file join $dir work]
set hdl [file join $root prj td lab_ex3_sc520 user_source hdl_source]
if {[catch {source [file join $root prj scripts sim_eram_model.tcl]
vlog -work work [file join $root src rtl osd logo_indexed_rom.v]
vlog -work work [file join $root src rtl osd detect_osd.v] [file join $root src rtl osd motion_osd.v] [file join $hdl osd_char_lib.v] [file join $hdl anlogic_logo_rom.v] [file join $hdl hdmi_mixer.v] [file join $root src sim tb_osd_math.v]} failure]} {puts stderr $failure;quit -force -code 1}
vsim -voptargs=+acc work.tb_osd_math $eram_sim_top
onfinish stop
run 1 ms
if {[examine -radix unsigned sim:/tb_osd_math/test_done]!=1 || [examine -radix decimal sim:/tb_osd_math/errors]!=0} {quit -force -code 1}
if {$is_batch} {quit -force -code 0}
