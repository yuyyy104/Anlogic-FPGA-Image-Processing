set root [file normalize [file join [file dirname [info script]] ../..]]
set sim_dir [file join $root tmp modelsim_pq_control]
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
set fd [open [file join $hdl design_top_wrapper.v] r]
fconfigure $fd -encoding utf-8
set top [read $fd]
close $fd
proc pq_instance {source marker} {
    set start [string first $marker $source]
    set end [string first ");" $source $start]
    if {$start<0 || $end<0} {error "Missing PQ instance: $marker"}
    return [string range $source $start [expr {$end+1}]]
}
set shell [open [file join $sim_dir pq_control_glue.v] w]
puts $shell {
module pq_control_glue(
    input S_24m_clk,S_cam_i2c_ready,S_cam_cfg_done,S_ae_cfg_done,
    input [1:0] S_ag_toggle,
    input S_manual_toggle,S_ae_toggle,
    input [27:0] S_ae_sum,
    output S_ae_req,S_ae_auto_valid,
    output [15:0] S_ae,S_ag
);
wire S_man_ae_req,S_manual_evt,S_ae_auto_req,S_exp_src_auto;
// This control test releases both resets together; power-up delay is separate.
wire S_rst_n=S_cam_i2c_ready;
wire S_lock_stable=1'b0;wire [19:0] S_ae_clipped=20'd0;
wire [15:0] S_man_ae,S_man_ag;
wire [10:0] S_ae_auto_ae;
wire [7:0] S_ae_auto_ag;
}
foreach marker {"ae_set u_ae_set" "ae_ctrl u_ae_ctrl" "exp_arb u_exp_arb"} {
    puts $shell [pq_instance $top $marker]
}
puts $shell "endmodule"
close $shell
if {[catch {
    vlog -work work [file join $root src rtl ctrl ae_ctrl.v] [file join $root src rtl ctrl exp_arb.v] \
        [file join $hdl uiisp_beta ae_set.v] [file join $sim_dir pq_control_glue.v] \
        [file join $hdl uics500_cfg uii2c.v] [file join $hdl uics520_cfg uics520reg_720p60.v] \
        [file join $hdl uics520_cfg uics520regAE.v] [file join $hdl uics520_cfg SC520GainTbl.v] \
        [file join $hdl uics520_cfg uicfgcs520.v] [file join $root src sim tb_sc520_config.v]
} failure]} {if {$is_batch} {quit -force -code 1}; error $failure}
vsim -voptargs=+acc -gPQ_TEST=1 work.tb_sc520_config
onfinish stop
run 400 ms
set finished [examine -radix unsigned sim:/tb_sc520_config/test_done]
set errors [examine -radix decimal sim:/tb_sc520_config/errors]
if {$finished!=1 || $errors!=0} {if {$is_batch} {quit -force -code 1}; error "PQ control failed or timed out"}
if {$is_batch} {quit -force -code 0}
