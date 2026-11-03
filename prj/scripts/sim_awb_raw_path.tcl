set root [file normalize [file join [file dirname [info script]] ../..]]
set sim_dir [file join $root tmp modelsim_awb_raw_path]
set is_batch [batch_mode]
onerror {quit -force -code 1}
proc checked_vlog {args} {if {[catch {eval vlog $args} failure]} {puts stderr $failure;quit -force -code 1}}
quit -sim
file mkdir $sim_dir
cd $sim_dir
transcript file [file join $sim_dir transcript.log]
vmap -c
if {![file isdirectory work]} {vlib work}
vmap work [file join $sim_dir work]
set lib D:/Software/Anlogic/TD_6.2.1_Engineer_6.2.168.116/sim_release/ph1p
checked_vlog -work work [file join $lib ph1p_phy_gsr.v] [file join $lib ph1p_logic_eram.v]
set hdl [file join $root prj td lab_ex3_sc520 user_source hdl_source]
set d [file join $hdl isp demosaic_4x_2_0]
foreach name {demosaic zhenghe} {
    set block [file join $d blk_mem_gen_$name]
    checked_vlog -work work [file join $block blk_mem_gen_${name}.v]
    foreach file [glob [file join $block RTL ram_*.v]] {checked_vlog -work work $file}
}
checked_vlog -work work [file join $root src rtl preproc isp_line_store.v]
foreach name {mipi_to_raw_converter zhenghe line_buffer_demosaic raw_matrix_3x3_buffer bilinear_interpolation demosaic} {
    checked_vlog -work work [file join $d ${name}.v]
}
checked_vlog -work work [file join $hdl isp data128_96 data128_96.v] [file join $root src rtl isp frame_awb.v] [file join $root src sim tb_awb_raw_path.v]
vsim -voptargs=+acc work.tb_awb_raw_path work.PH1P_PHY_GSR
onfinish stop
run 25 ms
if {[examine -radix unsigned sim:/tb_awb_raw_path/test_done]!=1 || [examine -radix decimal sim:/tb_awb_raw_path/errors]!=0} {quit -force -code 1}
if {$is_batch} {quit -force -code 0}
