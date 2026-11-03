set root [file normalize [file join [file dirname [info script]] ../..]]
set display_tb tb_color_multi_path
set display_duration {40 ms}
set display_calibration 1
set display_spatial 1
set display_multitarget 1
source [file join $root prj scripts sim_p3_display.tcl]
