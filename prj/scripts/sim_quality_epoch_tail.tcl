set root [file normalize [file join [file dirname [info script]] ../..]]
set p3_sim_dir [file join $root tmp modelsim_quality_epoch_tail]
set display_tb tb_quality_epoch_tail
set display_duration {1 ms}
source [file join $root prj scripts sim_p3_display.tcl]
