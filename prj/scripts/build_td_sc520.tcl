# Full baseline-derived build. Invoke td_commands_prompt.exe with forward slashes.
set root [file normalize [file join [file dirname [info script]] ../..]]
cd [file join $root prj td lab_ex3_sc520 td_project]
set build_start [clock seconds]
set build_dir [pwd]
if {[catch {
    import_device ph1_35p.db -package PH1P35MDG324 -speed 3
    open_project camera_to_dsi_display.al
    reset_runs syn_1
    launch_runs {syn_1 phy_1} -jobs 1
    wait_run syn_1 -quiet
    wait_run phy_1 -quiet
    open_run phy_1
    check_timing -verbose -file
    close_project
} failure]} {
    puts stderr "BUILD_FAILED: $failure"
    exit 1
}
set bit [file join $build_dir camera_to_dsi_display_Runs phy_1 camera_to_dsi_display.bit]
if {![file exists $bit] || [file size $bit] == 0 || [file mtime $bit] < $build_start} {
    puts stderr "BUILD_FAILED: missing, empty or stale bitstream"; exit 1
}
puts "BUILD_FINISHED: $bit (review current run reports before accepting timing)"
exit 0
