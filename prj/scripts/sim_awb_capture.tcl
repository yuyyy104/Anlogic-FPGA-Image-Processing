set root [file normalize [file join [file dirname [info script]] ../..]]
set sim_dir [file join $root tmp modelsim_awb_capture]
set hdl [file join $root prj td lab_ex3_sc520 user_source hdl_source]
set fifo [file join $root prj td lab_ex3_sc520 user_source ip_source w128_d512_fifo]
set is_batch [batch_mode]
onerror {quit -force -code 1}
quit -sim
file mkdir $sim_dir
cd $sim_dir
transcript file [file join $sim_dir transcript.log]
vmap -c
if {![file isdirectory work]} {vlib work}
vmap work [file join $sim_dir work]
if {[catch {
    vlog -sv -work work [file join $fifo w128_d512_fifo.v] [file join $fifo soft_fifo_al_4057d6b76aa6.v] \
        [file join $root src rtl isp frame_awb.v] [file join $hdl data_96bit_to_128bit.v] \
        [file join $hdl video_in.v] [file join $root src sim tb_awb_capture.v]
} failure]} {puts stderr $failure;quit -force -code 1}
vsim -voptargs=+acc work.tb_awb_capture
onfinish stop
run 20 ms
if {[examine -radix unsigned sim:/tb_awb_capture/test_done]!=1 || [examine -radix decimal sim:/tb_awb_capture/errors]!=0} {quit -force -code 1}
if {$is_batch} {quit -force -code 0}
