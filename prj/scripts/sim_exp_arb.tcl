set root [file normalize [file join [file dirname [info script]] ../..]]
set sim_dir [file join $root tmp modelsim_exp_arb]
set is_batch [batch_mode]
onerror {if {[batch_mode]} {quit -force -code 1} else {abort}}
quit -sim
file mkdir $sim_dir
cd $sim_dir
transcript file [file join $sim_dir transcript.log]
vmap -c
if {![file isdirectory work]} {vlib work}
vmap work [file join $sim_dir work]
vlog -work work [file join $root src rtl ctrl exp_arb.v]
if {[catch {vlog -work work [file join $root src sim tb_exp_arb.v]} msg]} {
    puts "COMPILE_FAILED: $msg"
    if {$is_batch} {quit -force -code 1}
    error "compile failed"
}
vsim -voptargs=+acc work.tb_exp_arb
onfinish stop
run 1 ms
set finished [examine -radix unsigned sim:/tb_exp_arb/test_done]
if {$finished != 1} {
    puts "TB_DID_NOT_FINISH"
    if {$is_batch} {quit -force -code 1}
    error "exp_arb TB did not finish"
}
set errors [examine -radix decimal sim:/tb_exp_arb/errors]
if {$errors != 0} {
    if {$is_batch} {quit -force -code 1}
    error "exp_arb TB failed"
}
if {$is_batch} {quit -force -code 0}
