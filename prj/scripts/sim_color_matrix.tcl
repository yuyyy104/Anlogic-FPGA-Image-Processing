# Fixed Q8 colour matrix: arithmetic, metadata and original DE contract.
set root [file normalize [file join [file dirname [info script]] ../..]]
set sim_dir [file join $root tmp modelsim_color_matrix]
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

vlog -work work [file join $root src rtl preproc shared_denoise.v]
vlog -work work [file join $root src rtl preproc line_delay.v]
vlog -work work [file join $root src rtl preproc line_delay_eram.v]
vlog -work work [file join $root src rtl ctrl ae_stats.v]
vlog -work work [file join $root src rtl preproc rgb2ycbcr.v]
vlog -work work [file join $root src rtl preproc preproc_pipe.v]
vlog -work work [file join $root src rtl detect detect_shape.v]
vlog -work work [file join $root src rtl motion frame_store.v]
vlog -work work [file join $root src rtl motion motion_sample.v]
vlog -work work [file join $root src rtl motion motion_mask.v]
vlog -work work [file join $root src rtl motion motion_runs.v]
vlog -work work [file join $root src rtl motion motion_labels.v]
vlog -work work [file join $root src rtl top video_display_pipe.v]
vlog -work work [file join $root src sim tb_color_matrix.v]

eval vsim -voptargs=+acc work.tb_color_matrix $eram_sim_top
onfinish stop
if {!$is_batch} {
    view wave
    add wave sim:/tb_color_matrix/clk sim:/tb_color_matrix/rst
    add wave -radix binary sim:/tb_color_matrix/req
    add wave sim:/tb_color_matrix/rd
    add wave -radix hex sim:/tb_color_matrix/rgb sim:/tb_color_matrix/dut/color_rgb
    add wave -radix binary sim:/tb_color_matrix/dut/color_timing
}
run 20 ms
set finished [examine -radix unsigned sim:/tb_color_matrix/test_done]
set errors [examine -radix decimal sim:/tb_color_matrix/errors]
if {$finished != 1 || $errors != 0} {
    if {$is_batch} {quit -force -code 1}
    error "video_adapter failed or timed out"
}
if {$is_batch} {quit -force -code 0}
