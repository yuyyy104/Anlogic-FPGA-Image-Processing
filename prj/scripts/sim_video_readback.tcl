set root [file normalize [file join [file dirname [info script]] ../..]]
set sim_dir [file join $root tmp modelsim_video_readback]
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
source [file join $root prj scripts sim_eram_model.tcl]
vlog -work work [file join $root src rtl osd logo_indexed_rom.v]
vlog -work work [file join $root src rtl preproc shared_denoise.v]
vlog -work work [file join $root src rtl preproc line_delay.v] \
    [file join $root src rtl preproc line_delay_eram.v] \
    [file join $root src rtl ctrl ae_stats.v] \
     [file join $root src rtl preproc rgb2ycbcr.v] \
     [file join $root src rtl preproc preproc_pipe.v] \
     [file join $root src rtl detect detect_shape.v] [file join $root src rtl osd detect_osd.v] \
     [file join $root src rtl motion frame_store.v] [file join $root src rtl motion motion_sample.v] \
     [file join $root src rtl motion motion_mask.v] \
     [file join $root src rtl motion motion_runs.v] \
    [file join $root src rtl motion motion_labels.v] \
    [file join $root src rtl osd motion_osd.v] \
     [file join $root src rtl ctrl color_sample.v] [file join $root src rtl top video_display_pipe.v] [file join $hdl video_out.v] [file join $hdl hdmi_mixer.v] [file join $hdl osd_char_lib.v] [file join $hdl anlogic_logo_rom.v] [file join $root src sim tb_video_readback.v]
eval vsim -voptargs=+acc work.tb_video_readback $eram_sim_top
log -r /*
if {!$is_batch} {
    view wave
    add wave sim:/tb_video_readback/clk sim:/tb_video_readback/rst_n sim:/tb_video_readback/read_en
    add wave -radix hexadecimal sim:/tb_video_readback/stimulus_rgb sim:/tb_video_readback/read_rgb sim:/tb_video_readback/processed_rgb sim:/tb_video_readback/hdmi_rgb
    add wave sim:/tb_video_readback/timing sim:/tb_video_readback/processed_timing sim:/tb_video_readback/hd
}
run 150 us
set finished [examine -radix unsigned sim:/tb_video_readback/test_done]
set errors [examine -radix decimal sim:/tb_video_readback/errors]
if {$finished != 1 || $errors != 0} {
    if {$is_batch} {quit -force -code 1}
    error "Readback test failed or timed out"
}
if {$is_batch} {quit -force -code 0}
wave zoom range 2700ns 3100ns
