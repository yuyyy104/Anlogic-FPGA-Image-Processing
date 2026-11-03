set root [file normalize [file join [file dirname [info script]] ../..]]
set sim_dir [file join $root tmp modelsim_frame_meta_path]
set hdl [file join $root prj td lab_ex3_sc520 user_source hdl_source]
set fifo [file join $root prj td lab_ex3_sc520 user_source ip_source w128_d512_fifo]
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
vlog -sv -work work [file join $fifo w128_d512_fifo.v] [file join $fifo soft_fifo_al_4057d6b76aa6.v] \
        [file join $hdl data_96bit_to_128bit.v] [file join $hdl video_in.v] [file join $hdl video_out.v] [file join $root src rtl ctrl frame_meta.v] \
        [file join $root src rtl osd detect_osd.v] [file join $root src rtl osd motion_osd.v] \
        [file join $hdl hdmi_mixer.v] [file join $hdl osd_char_lib.v] [file join $hdl anlogic_logo_rom.v] \
        [file join $root src sim tb_frame_meta_path.v]
} failure]} {
    puts "COMPILE_FAILED: $failure"
    if {$is_batch} {quit -force -code 1}
    error $failure
}
vsim -voptargs=+acc work.tb_frame_meta_path $eram_sim_top
onfinish stop
run 100 ms
set finished [examine -radix unsigned sim:/tb_frame_meta_path/test_done]
set errors [examine -radix decimal sim:/tb_frame_meta_path/errors]
if {$finished != 1 || $errors != 0} {
    if {$is_batch} {quit -force -code 1}
    error "frame_meta_path failed or timed out"
}
if {$is_batch} {quit -force -code 0}
