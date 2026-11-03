set root [file normalize [file join [file dirname [info script]] ../..]]
set sim_dir [file join $root tmp modelsim_i2c_reset]
set is_batch [batch_mode]
onerror {if {[batch_mode]} {quit -force -code 1} else {abort}}
quit -sim
file mkdir $sim_dir
cd $sim_dir
transcript file [file join $sim_dir transcript.log]
vmap -c
if {![file isdirectory work]} {vlib work}
vmap work [file join $sim_dir work]
vlog -work work [file join $root prj td lab_ex3_sc520 user_source hdl_source uics500_cfg uii2c.v] [file join $root src sim tb_i2c_reset.v]
vsim -voptargs=+acc work.tb_i2c_reset
log -r /*
if {!$is_batch} {
    view wave
    add wave sim:/tb_i2c_reset/clk sim:/tb_i2c_reset/rst_n sim:/tb_i2c_reset/dut/reset_release_n sim:/tb_i2c_reset/dut/scl_clk sim:/tb_i2c_reset/req sim:/tb_i2c_reset/scl sim:/tb_i2c_reset/sda sim:/tb_i2c_reset/busy sim:/tb_i2c_reset/bus_error
}
run 5 ms
set finished [examine -radix unsigned sim:/tb_i2c_reset/test_done]
set errors [examine -radix decimal sim:/tb_i2c_reset/errors]
if {$finished != 1 || $errors != 0} {
    if {$is_batch} {quit -force -code 1}
    error "I2C reset test failed or timed out"
}
if {$is_batch} {quit -force -code 0}
wave zoom range 0ns 5000ns
