set root [file normalize [file join [file dirname [info script]] ../..]]
set sim_dir [file join $root tmp modelsim_mode_osd]
set hdl [file join $root prj td lab_ex3_sc520 user_source hdl_source]
set is_batch [batch_mode]
onerror {if {[batch_mode]} {quit -force -code 1} else {abort}}
quit -sim
file mkdir $sim_dir
cd $sim_dir
transcript file [file join $sim_dir transcript.log]
vmap -c
if {![file isdirectory work]} {vlib work}
vmap work [file join $sim_dir work]
if {[catch {
source [file join $root prj scripts sim_eram_model.tcl]
vlog -work work [file join $root src rtl osd logo_indexed_rom.v]
vlog -work work [file join $root src rtl osd detect_osd.v] [file join $root src rtl osd motion_osd.v] [file join $hdl hdmi_mixer.v] [file join $hdl osd_char_lib.v] [file join $hdl anlogic_logo_rom.v] [file join $root src sim tb_mode_osd.v]
} failure]} {if {$is_batch} {quit -force -code 1}; error $failure}
vsim -voptargs=+acc work.tb_mode_osd $eram_sim_top
onfinish stop
run 3 ms
set finished [examine -radix unsigned sim:/tb_mode_osd/test_done]
set errors [examine -radix decimal sim:/tb_mode_osd/errors]
if {$finished != 1 || $errors != 0} {
    if {$is_batch} {quit -force -code 1}
    error "Mode OSD failed or timed out"
}
if {$is_batch} {quit -force -code 0}
