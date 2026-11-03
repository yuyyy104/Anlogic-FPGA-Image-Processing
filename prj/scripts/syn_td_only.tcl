# 只跑综合并输出资源报告，用于快速判断 ERAM 推断是否生效（不必等完整布局布线）。
set root [file normalize [file join [file dirname [info script]] ../..]]
cd [file join $root prj td lab_ex3_sc520 td_project]
if {[catch {
    import_device ph1_35p.db -package PH1P35MDG324 -speed 3
    open_project camera_to_dsi_display.al
    reset_runs syn_1
    launch_runs syn_1 -jobs 1
    wait_run syn_1 -quiet
    close_project
} failure]} {
    puts stderr "SYN_FAILED: $failure"
    exit 1
}
puts "SYN_FINISHED"
exit 0
