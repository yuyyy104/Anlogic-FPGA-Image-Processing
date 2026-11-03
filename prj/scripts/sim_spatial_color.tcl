# Fixed Q8 colour matrix: arithmetic, metadata and original DE contract.
set root [file normalize [file join [file dirname [info script]] ../..]]
set sim_dir [file join $root tmp modelsim_spatial_color]
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

vlog -work work [file join $root src rtl isp spatial_color.v]
vlog -work work [file join $root src sim tb_spatial_color.v]

vsim -voptargs=+acc work.tb_spatial_color
onfinish stop
if {!$is_batch} {
    view wave
    add wave sim:/tb_spatial_color/clk sim:/tb_spatial_color/rst
    add wave -radix binary sim:/tb_spatial_color/t
    add wave sim:/tb_spatial_color/ot
    add wave -radix hex sim:/tb_spatial_color/rgb sim:/tb_spatial_color/actual
    add wave -radix binary sim:/tb_spatial_color/ot
}
run 30 ms
set finished [examine -radix unsigned sim:/tb_spatial_color/test_done]
set errors [examine -radix decimal sim:/tb_spatial_color/errors]
if {$finished != 1 || $errors != 0} {
    if {$is_batch} {quit -force -code 1}
    error "video_adapter failed or timed out"
}
if {$is_batch} {quit -force -code 0}
