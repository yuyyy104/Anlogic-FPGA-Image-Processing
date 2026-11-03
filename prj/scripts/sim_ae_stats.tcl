set root [file normalize [file join [file dirname [info script]] ../..]]
set sim_dir [file join $root tmp modelsim_ae_stats]
set is_batch [batch_mode]
onerror {if {[batch_mode]} {quit -force -code 1} else {abort}}
quit -sim
file mkdir $sim_dir
cd $sim_dir
transcript file [file join $sim_dir transcript.log]
vmap -c
if {![file isdirectory work]} {vlib work}
vmap work [file join $sim_dir work]
vlog -work work [file join $root src rtl ctrl ae_stats.v]
if {[catch {vlog -work work [file join $root src sim tb_ae_stats.v]} msg]} {
    puts "COMPILE_FAILED: $msg"
    if {$is_batch} {quit -force -code 1}
    error "compile failed"
}
vsim -voptargs=+acc work.tb_ae_stats
onfinish stop
run 20 ms
set finished [examine -radix unsigned sim:/tb_ae_stats/test_done]
if {$finished != 1} {
    puts "TB_DID_NOT_FINISH"
    if {$is_batch} {quit -force -code 1}
    error "ae_stats TB did not finish"
}
set errors [examine -radix decimal sim:/tb_ae_stats/errors]
if {$errors != 0} {
    if {$is_batch} {quit -force -code 1}
    error "ae_stats TB failed"
}
if {$is_batch} {quit -force -code 0}
