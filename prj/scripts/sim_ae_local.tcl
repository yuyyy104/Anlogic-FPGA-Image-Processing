set root [file normalize [file join [file dirname [info script]] ../..]]
set dir [file join $root tmp modelsim_ae_local]
set is_batch [batch_mode]
onerror {quit -force -code 1}
quit -sim
file mkdir $dir
cd $dir
transcript file [file join $dir transcript.log]
vmap -c
if {![file isdirectory work]} {vlib work}
vmap work [file join $dir work]
if {[catch {vlog -work work {D:/codex_project/FPGA_competiton/src/rtl/ctrl/ae_stats.v} {D:/codex_project/FPGA_competiton/src/rtl/ctrl/ae_ctrl.v} {D:/codex_project/FPGA_competiton/src/sim/tb_ae_local.v}} err]} {puts stderr $err;quit -force -code 1}
vsim -voptargs=+acc work.tb_ae_local
onfinish stop
run 20 ms
if {[examine -radix unsigned sim:/tb_ae_local/test_done]!=1 || [examine -radix decimal sim:/tb_ae_local/errors]!=0} {quit -force -code 1}
if {$is_batch} {quit -force -code 0}
