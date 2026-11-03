# sim_video_frame.tcl —�?完整 1280x720 �?VTC 消隐的全帧联合测试（P2�?
set root [file normalize [file join [file dirname [info script]] ../..]]
set sim_dir [file join $root tmp modelsim_frame]
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
vlog -work work [file join $root src sim tb_video_frame.v]

eval vsim -voptargs=+acc work.tb_video_frame $eram_sim_top
onfinish stop
# 7 个模式各跑一整帧 + 切换测试，共�?12 �?x 750 �?x 1650 �?
run 400 ms
set finished [examine -radix unsigned sim:/tb_video_frame/test_done]
set errors [examine -radix decimal sim:/tb_video_frame/errors]
if {$finished != 1 || $errors != 0} {
    if {$is_batch} {quit -force -code 1}
    error "video_frame failed or timed out"
}
if {$is_batch} {quit -force -code 0}
