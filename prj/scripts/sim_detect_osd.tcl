set root [file normalize [file join [file dirname [info script]] ../..]]
set sim_dir [file join $root tmp modelsim_detect_osd]
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
vlog -work work [file join $root src rtl osd detect_osd.v]
vlog -work work [file join $hdl osd_char_lib.v]
vlog -work work [file join $root src sim tb_detect_osd.v]

vsim -voptargs=+acc work.tb_detect_osd
onfinish stop
if {!$is_batch} {
    view wave
    add wave sim:/tb_detect_osd/clk sim:/tb_detect_osd/ov_valid
    add wave -radix hexadecimal sim:/tb_detect_osd/ov_rgb
    add wave -radix unsigned sim:/tb_detect_osd/x_2d sim:/tb_detect_osd/y_2d
}
run 30 ms
set finished [examine -radix unsigned sim:/tb_detect_osd/test_done]
set errors [examine -radix decimal sim:/tb_detect_osd/errors]
if {$finished != 1 || $errors != 0} {
    if {$is_batch} {quit -force -code 1}
    error "detect_osd failed or timed out"
}
if {$is_batch} {quit -force -code 0}
