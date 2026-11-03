# sim_preproc.tcl —�?预处�?风格化流水线逐像素验证（P2�?
set root [file normalize [file join [file dirname [info script]] ../..]]
set sim_dir [file join $root tmp modelsim_preproc]
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

vlog -work work [file join $root src rtl preproc line_delay.v]
vlog -work work [file join $root src rtl preproc line_delay_eram.v]
vlog -work work [file join $root src rtl ctrl ae_stats.v]
vlog -work work [file join $root src rtl preproc rgb2ycbcr.v]
vlog -work work [file join $root src rtl preproc preproc_pipe.v]
vlog -work work [file join $root src sim tb_preproc.v]

eval vsim -voptargs=+acc work.tb_preproc $eram_sim_top
onfinish stop
if {!$is_batch} {
    view wave
    add wave sim:/tb_preproc/clk sim:/tb_preproc/rst_n
    add wave sim:/tb_preproc/rgb_in sim:/tb_preproc/rgb_out
    add wave sim:/tb_preproc/timing_in sim:/tb_preproc/timing_out
    add wave -radix unsigned sim:/tb_preproc/mode
}
# 7 模式 x 15 图案 + 稳定�?消隐/复位用例，每�?3~4 �?
run 60 ms
set finished [examine -radix unsigned sim:/tb_preproc/test_done]
set errors [examine -radix decimal sim:/tb_preproc/errors]
if {$finished != 1 || $errors != 0} {
    if {$is_batch} {quit -force -code 1}
    error "preproc failed or timed out"
}
if {$is_batch} {quit -force -code 0}
