set root [file normalize [file join [file dirname [info script]] ../..]]
set dir [file join $root tmp modelsim_switch_debounce]
set is_batch [batch_mode]
onerror {if {[batch_mode]} {quit -force -code 1} else {abort}}
proc checked_vlog {args} {
    if {[catch {eval vlog $args} failure]} {puts stderr $failure; quit -force -code 1}
}
quit -sim
file mkdir $dir
cd $dir
transcript file [file join $dir transcript.log]
vmap -c
if {![file isdirectory work]} {vlib work}
vmap work [file join $dir work]
checked_vlog -work work [file join $root src rtl ctrl switch_debounce.v] [file join $root src sim tb_switch_debounce.v]
vsim -voptargs=+acc work.tb_switch_debounce
onfinish stop
run 1 ms
if {[examine -radix unsigned sim:/tb_switch_debounce/test_done]!=1 || [examine -radix decimal sim:/tb_switch_debounce/errors]!=0} {quit -force -code 1}
if {$is_batch} {quit -force -code 0}
