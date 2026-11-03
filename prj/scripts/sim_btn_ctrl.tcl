# sim_btn_ctrl.tcl - KEY1/KEY2 operation and KEY3/KEY4 disabled
set root [file normalize [file join [file dirname [info script]] ../..]]
set sim_dir [file join $root tmp modelsim_btn]
set is_batch [batch_mode]
onerror {if {[batch_mode]} {quit -force -code 1} else {abort}}
quit -sim
file mkdir $sim_dir
cd $sim_dir
transcript file [file join $sim_dir transcript.log]
vmap -c
if {![file isdirectory work]} {vlib work}
vmap work [file join $sim_dir work]

vlog -work work [file join $root src rtl ctrl btn_mode_ctrl.v]
vlog -work work [file join $root src sim tb_btn_ctrl.v]

vsim -voptargs=+acc work.tb_btn_ctrl
onfinish stop
if {!$is_batch} {
    view wave
    add wave sim:/tb_btn_ctrl/clk sim:/tb_btn_ctrl/rst_n
    add wave -radix binary sim:/tb_btn_ctrl/btn
    add wave -radix unsigned sim:/tb_btn_ctrl/mode
    add wave -radix unsigned sim:/tb_btn_ctrl/thresh
}
run 20 ms
set finished [examine -radix unsigned sim:/tb_btn_ctrl/test_done]
set errors [examine -radix decimal sim:/tb_btn_ctrl/errors]
if {$finished != 1 || $errors != 0} {
    if {$is_batch} {quit -force -code 1}
    error "btn_ctrl failed or timed out"
}
if {$is_batch} {quit -force -code 0}
