set root [file normalize [file join [file dirname [info script]] ../..]]
set dir [file join $root tmp modelsim_calibration_osd]
set is_batch [batch_mode]
onerror {quit -force -code 1}
quit -sim
file mkdir $dir
cd $dir
transcript file [file join $dir transcript.log]
vmap -c
if {![file isdirectory work]} {vlib work}
vmap work [file join $dir work]
if {[catch {vlog -work work {D:/codex_project/FPGA_competiton/src/rtl/osd/calibration_osd.v} {D:/codex_project/FPGA_competiton/prj/td/lab_ex3_sc520/user_source/hdl_source/osd_char_lib.v} {D:/codex_project/FPGA_competiton/src/sim/tb_calibration_osd.v}} err]} {puts stderr $err;quit -force -code 1}
vsim -voptargs=+acc work.tb_calibration_osd
onfinish stop
run 20 ms
if {[examine -radix unsigned sim:/tb_calibration_osd/test_done]!=1 || [examine -radix decimal sim:/tb_calibration_osd/errors]!=0} {quit -force -code 1}
if {$is_batch} {quit -force -code 0}
