set root [file normalize [file join [file dirname [info script]] ../..]]
set sim_dir [file join $root tmp modelsim_i2c_caller]
set is_batch [batch_mode]
onerror {if {[batch_mode]} {quit -force -code 1} else {abort}}
quit -sim
file mkdir $sim_dir
cd $sim_dir
transcript file [file join $sim_dir transcript.log]
vmap -c
if {![file isdirectory work]} {vlib work}
vmap work [file join $sim_dir work]
set hdl [file join $root prj td lab_ex3_sc520 user_source hdl_source uics500_cfg]
foreach f {uii2c.v uicfgcs500_720p.v uics500reg_720p60.v SC500GainTbl.v uics500regAE.v} {
    vlog -work work [file join $hdl $f]
}
vlog -work work [file join $root src sim tb_i2c_caller.v]
vsim -voptargs=+acc work.tb_i2c_caller
# Avoid recording every internal transition in the full 116-register boot sequence.
log sim:/tb_i2c_caller/clk sim:/tb_i2c_caller/rst_n sim:/tb_i2c_caller/scl sim:/tb_i2c_caller/sda sim:/tb_i2c_caller/transactions
if {!$is_batch} {
    view wave
    add wave sim:/tb_i2c_caller/clk sim:/tb_i2c_caller/rst_n sim:/tb_i2c_caller/scl sim:/tb_i2c_caller/sda sim:/tb_i2c_caller/cfg_done sim:/tb_i2c_caller/ae_done sim:/tb_i2c_caller/dut/iic_busy
}
run 30 ms
set finished [examine -radix unsigned sim:/tb_i2c_caller/test_done]
set errors [examine -radix decimal sim:/tb_i2c_caller/errors]
if {$finished != 1 || $errors != 0} {
    if {$is_batch} {quit -force -code 1}
    error "I2C caller test failed or timed out"
}
if {$is_batch} {quit -force -code 0}
wave zoom full
