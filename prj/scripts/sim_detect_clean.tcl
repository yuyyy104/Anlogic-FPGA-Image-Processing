set root [file normalize [file join [file dirname [info script]] ../..]]
set sim_dir [file join $root tmp modelsim_detect_clean]
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
vlog -work work [file join $root src rtl detect detect_shape.v]
vlog -work work [file join $root src sim tb_detect.v]

if {![info exists detect_cleanup]} {set detect_cleanup 1}
eval vsim -voptargs=+acc -gCLEANUP=$detect_cleanup work.tb_detect $eram_sim_top
onfinish stop
if {!$is_batch} {
    view wave
    add wave sim:/tb_detect/clk sim:/tb_detect/rst_n
    add wave -radix unsigned sim:/tb_detect/res_area sim:/tb_detect/res_cls
    add wave sim:/tb_detect/res_valid sim:/tb_detect/res_xmin sim:/tb_detect/res_xmax
    add wave sim:/tb_detect/res_ymin sim:/tb_detect/res_ymax
}
run 20 ms
set finished [examine -radix unsigned sim:/tb_detect/test_done]
set errors [examine -radix decimal sim:/tb_detect/errors]
if {$finished != 1 || $errors != 0} {
    if {$is_batch} {quit -force -code 1}
    error "detect failed or timed out"
}
if {$is_batch} {quit -force -code 0}
