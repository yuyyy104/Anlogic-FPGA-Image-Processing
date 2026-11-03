set root [file normalize [file join [file dirname [info script]] ../..]]
set sim_dir [file join $root tmp modelsim_line_delay_eram]
set is_batch [batch_mode]
onerror {if {[batch_mode]} {quit -force -code 1} else {abort}}
quit -sim
file mkdir $sim_dir
cd $sim_dir
transcript file [file join $sim_dir transcript.log]
vmap -c
if {![file isdirectory work]} {vlib work}
vmap work [file join $sim_dir work]
source [file join $root prj scripts sim_eram_model.tcl]
# the vendor primitive is stubbed behaviourally for simulation only
vlog -work work [file join $root src rtl preproc line_delay_eram.v]
if {[catch {vlog -work work [file join $root src sim tb_line_delay_eram.v]} msg]} {
    puts "COMPILE_FAILED: $msg"
    if {$is_batch} {quit -force -code 1}
    error "compile failed"
}
eval vsim -voptargs=+acc work.tb_line_delay_eram $eram_sim_top
onfinish stop
run 20 ms
set finished [examine -radix unsigned sim:/tb_line_delay_eram/test_done]
if {$finished != 1} {
    puts "TB_DID_NOT_FINISH"
    if {$is_batch} {quit -force -code 1}
    error "line_delay_eram TB did not finish"
}
set errors [examine -radix decimal sim:/tb_line_delay_eram/errors]
if {$errors != 0} {
    if {$is_batch} {quit -force -code 1}
    error "line_delay_eram TB failed"
}
if {$is_batch} {quit -force -code 0}
