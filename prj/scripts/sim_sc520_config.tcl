# sim_sc520_config.tcl —— SC520 配置流程验证（P1）
# 编译最小依赖集：uii2c + uicfgcs520 + SC520 寄存器表 + 增益表 + TB
set root [file normalize [file join [file dirname [info script]] ../..]]
set sim_dir [file join $root tmp modelsim_sc520_config]
set is_batch [batch_mode]
onerror {if {[batch_mode]} {quit -force -code 1} else {abort}}
quit -sim
file mkdir $sim_dir
cd $sim_dir
transcript file [file join $sim_dir transcript.log]
vmap -c
if {![file isdirectory work]} {vlib work}
vmap work [file join $sim_dir work]

set cfg [file join $root prj td lab_ex3_sc520 user_source hdl_source uics520_cfg]
set i2c [file join $root prj td lab_ex3_sc520 user_source hdl_source uics500_cfg]

# uii2c 为共用控制器（GBK 编码，模型自身不影响）
vlog -work work [file join $i2c uii2c.v]
vlog -work work [file join $cfg uics520reg_720p60.v]
vlog -work work [file join $cfg uics520regAE.v]
vlog -work work [file join $cfg SC520GainTbl.v]
vlog -work work [file join $cfg uicfgcs520.v]
vlog -work work [file join $root src sim tb_sc520_config.v]

vsim -voptargs=+acc work.tb_sc520_config
onfinish stop
if {!$is_batch} {
    view wave
    add wave sim:/tb_sc520_config/clk sim:/tb_sc520_config/rst_n
    add wave sim:/tb_sc520_config/scl sim:/tb_sc520_config/sda
    add wave -radix hex sim:/tb_sc520_config/sensor_id
    add wave sim:/tb_sc520_config/sensor_id_ok sim:/tb_sc520_config/iic_error
    add wave sim:/tb_sc520_config/cfg_done sim:/tb_sc520_config/ae_done
}

# S8 完整序列：165 笔 4 字节写在约 100 kHz 下约 59 ms（165×4×9×9996 ns），
# 加首条后 5 ms 等待与 8 笔 AE；实测 $finish 在 158508656 ns（约 158 ms）。
# 脚本以 test_done/errors 判定，不按时长；这里留 300 ms 余量。
run 300 ms
set finished [examine -radix unsigned sim:/tb_sc520_config/test_done]
set errors [examine -radix decimal sim:/tb_sc520_config/errors]
if {$finished != 1 || $errors != 0} {
    if {$is_batch} {quit -force -code 1}
    error "SC520 config test failed or timed out"
}
if {$is_batch} {quit -force -code 0}
