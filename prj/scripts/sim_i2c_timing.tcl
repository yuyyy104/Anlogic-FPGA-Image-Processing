set root [file normalize [file join [file dirname [info script]] ../..]]
set sim_dir [file join $root tmp modelsim_i2c_timing]
set is_batch [batch_mode]
onerror {if {[batch_mode]} {quit -force -code 1} else {abort}}
quit -sim
file mkdir $sim_dir
cd $sim_dir
transcript file [file join $sim_dir transcript.log]
vmap -c
if {![file isdirectory work]} {vlib work}
vmap work [file join $sim_dir work]
vlog -work work [file join $root prj td lab_ex3_sc520 user_source hdl_source uics500_cfg uii2c.v] [file join $root src sim tb_i2c_timing.v]
vsim -voptargs=+acc work.tb_i2c_timing
log -r /*
if {!$is_batch} {
    view wave
    add wave sim:/tb_i2c_timing/clk sim:/tb_i2c_timing/rst_n sim:/tb_i2c_timing/dut/reset_release_n sim:/tb_i2c_timing/dut/scl_clk sim:/tb_i2c_timing/req sim:/tb_i2c_timing/scl sim:/tb_i2c_timing/sda sim:/tb_i2c_timing/busy sim:/tb_i2c_timing/bus_error
}
run 15 ms
set finished [examine -radix unsigned sim:/tb_i2c_timing/test_done]
set errors [examine -radix decimal sim:/tb_i2c_timing/errors]
if {$finished != 1 || $errors != 0} {
    if {$is_batch} {quit -force -code 1}
    error "I2C timing test failed or timed out"
}
if {$is_batch} {quit -force -code 0}
wave zoom range 0ns 5000ns
