set root [file normalize [file join [file dirname [info script]] ../..]]
set sim_dir [file join $root tmp modelsim_detect_big]
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
vlog -work work [file join $root src sim tb_detect_big.v]

if {![info exists detect_noise]} {set detect_noise 0}
eval vsim -voptargs=+acc -gNOISE=$detect_noise work.tb_detect_big $eram_sim_top
onfinish stop
if {!$is_batch} {
    view wave
    add wave -radix unsigned sim:/tb_detect_big/res_area sim:/tb_detect_big/res_cls
    add wave sim:/tb_detect_big/res_valid
}
run 70 ms
set finished [examine -radix unsigned sim:/tb_detect_big/test_done]
set errors [examine -radix decimal sim:/tb_detect_big/errors]
if {$finished != 1 || $errors != 0} {
    if {$is_batch} {quit -force -code 1}
    error "detect_big failed or timed out"
}
if {$is_batch} {quit -force -code 0}
