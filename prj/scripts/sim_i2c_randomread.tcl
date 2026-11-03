# sim_i2c_randomread.tcl —— uii2c 随机读路径最小用例（P1 关键判别）
set root [file normalize [file join [file dirname [info script]] ../..]]
set sim_dir [file join $root tmp modelsim_i2c_randomread]
set is_batch [batch_mode]
onerror {if {[batch_mode]} {quit -force -code 1} else {abort}}
quit -sim
file mkdir $sim_dir
cd $sim_dir
transcript file [file join $sim_dir transcript.log]
vmap -c
if {![file isdirectory work]} {vlib work}
vmap work [file join $sim_dir work]

vlog -work work [file join $root prj td lab_ex3_sc520 user_source hdl_source uics500_cfg uii2c.v]
vlog -work work [file join $root src sim tb_i2c_randomread.v]

vsim -voptargs=+acc work.tb_i2c_randomread
log -r /*
if {!$is_batch} {
    view wave
    add wave sim:/tb_i2c_randomread/clk sim:/tb_i2c_randomread/rst_n
    add wave sim:/tb_i2c_randomread/scl sim:/tb_i2c_randomread/sda
    add wave sim:/tb_i2c_randomread/busy sim:/tb_i2c_randomread/bus_error
    add wave -radix hex sim:/tb_i2c_randomread/rd_data
    add wave sim:/tb_i2c_randomread/dut/IIC_S
}
run 40 ms
if {$is_batch} {quit -force -code 0}
