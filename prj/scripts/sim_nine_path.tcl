set root [file normalize [file join [file dirname [info script]] ../..]]
set display_tb tb_nine_path
set display_duration {65 ms}
set display_calibration 1
set display_spatial 1
set display_width 1024
set display_height 512
set display_status_cdc 1
source [file join $root prj scripts sim_p3_display.tcl]
