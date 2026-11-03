set root [file normalize [file join [file dirname [info script]] ../..]]
set p3_sim_dir [file join $root tmp modelsim_calibration_path]
set display_tb tb_calibration_path
set display_duration {30 ms}
set display_calibration 1
source [file join $root prj scripts sim_p3_display.tcl]
