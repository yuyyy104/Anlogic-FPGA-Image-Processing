set root [file normalize [file join [file dirname [info script]] ../..]]
set dir [file join $root tmp modelsim_awb_status_cdc]
set is_batch [batch_mode]
onerror {quit -force -code 1}
quit -sim
file mkdir $dir
cd $dir
transcript file [file join $dir transcript.log]
vmap -c
if {![file isdirectory work]} {vlib work}
vmap work [file join $dir work]
if {[catch {vlog -work work {D:/codex_project/FPGA_competiton/src/rtl/ctrl/awb_status_cdc.v} {D:/codex_project/FPGA_competiton/src/sim/tb_awb_status_cdc.v}} err]} {puts stderr $err;quit -force -code 1}
vsim -voptargs=+acc work.tb_awb_status_cdc
onfinish stop
run 20 ms
if {[examine -radix unsigned sim:/tb_awb_status_cdc/test_done]!=1 || [examine -radix decimal sim:/tb_awb_status_cdc/errors]!=0} {quit -force -code 1}
if {$is_batch} {quit -force -code 0}
