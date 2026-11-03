set root [file normalize [file join [file dirname [info script]] ../..]]
if {![info exists p3_sim_dir]} {set p3_sim_dir [file join $root tmp modelsim_p3_display]}
set sim_dir $p3_sim_dir
if {![info exists display_tb]} {set display_tb tb_p3_display}
if {![info exists display_duration]} {set display_duration {60 ms}}
set hdl [file join $root prj td lab_ex3_sc520 user_source hdl_source]
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

# Compile the two actual top-level instances, including their actual wiring.
# Encrypted camera/DDR/HDMI IP remains outside this display-side simulation.
if {![info exists p3_top_source]} {set p3_top_source [file join $hdl design_top_wrapper.v]}
set fd [open $p3_top_source r]
fconfigure $fd -encoding utf-8
set top_source [read $fd]
close $fd
proc display_instance {source marker name} {
    set start [string first $marker $source]
    if {$start < 0} {error "Missing display instance: $name"}
    set end [string first ");" $source $start]
    if {$end < 0} {error "Unterminated display instance: $name"}
    set instance [string range $source $start [expr {$end + 1}]]
    if {[string first $name $instance] < 0} {error "Unexpected display instance: $name"}
    return $instance
}
set shell [open [file join $sim_dir p3_display_glue.v] w]
puts $shell {
module p3_display_glue (
    input S_hdmi_pixel_clk, S_hdmi_rst_n,
    input [23:0] S_video_rd_data,
    input S_hdmi_vsync, S_hdmi_hsync, S_hdmi_de, S_hdmi_user, S_hdmi_last,
    input [3:0] S_preproc_mode, S_hdmi_debug_status,
    input [7:0] S_preproc_thresh,
    output S_hdmi_window_rd_en,
    output S_hdmi_out_vsync, S_hdmi_out_hsync, S_hdmi_out_de,
    output [23:0] S_hdmi_out_data
);
    localparam PREPROC_MODE = 0;
    wire [23:0] S_processed_rgb;
    wire [4:0] S_processed_timing;
    wire [3:0] S_active_mode;
    wire S_cal_stable=1'b0,S_lock_stable=1'b0,S_awb_frozen=1'b0;
    wire [215:0] S_cal_regions_in,S_cal_regions_out;wire [116:0] S_cal_regions_clip_in,S_cal_regions_clip_out;wire S_cal_regions_valid;
    wire [23:0] S_cal_rgb;wire [12:0] S_cal_clipped;wire S_cal_valid;wire [2:0] S_det_reason;wire [19:0] S_ae_clipped;
    wire S_denoise_stable=1'b0;
    wire S_active_denoise;
    wire [7:0] S_active_thresh;
    wire S_det_valid;
    wire S_targets_valid,S_targets_overflow;wire [7:0] S_targets_count;
    wire [11:0] S_targets_colors,S_targets_shapes;wire [79:0] S_targets_areas;wire [191:0] S_targets_boxes;
    wire [1:0] S_det_cls;
    wire [19:0] S_det_area;
    wire [11:0] S_det_xmin, S_det_xmax, S_det_ymin, S_det_ymax;
    wire [15:0] S_mv_count;
    wire S_mv_valid;
    wire [23:0] S_mv_frame_id;
    wire S_mv_mask_ce;
    wire [7:0] S_mv_mask_byte;
    wire [7:0] S_mv_mask_x0;
    wire S_mv_mask_end;
    wire S_mv_mask_overflow;
    wire [15:0] S_mv_mask_cells;
    wire S_mv_run_valid;
    wire [7:0] S_mv_run_x0;
    wire [7:0] S_mv_run_x1;
    wire [7:0] S_mv_run_y;
    wire S_mv_run_row_end;
    wire [15:0] S_mv_run_count;
    wire S_mv_runs_overflow;
    wire S_mv_scan_overflow;
    wire S_mv_regions_valid;
    wire S_exp_src_auto;
    wire [27:0] S_ae_sum;
    wire [19:0] S_ae_n;
    wire S_ae_toggle,S_ae_valid;
    wire [1:0] S_ae_local_high;
    wire [40:0] S_awb_status=41'd0;
    // 测试壳：默认自动；真实顶层里该网由 exp_arb.o_src_auto 驱动（源=ae_ctrl.auto_valid）
    assign S_exp_src_auto = 1'b1;
    wire [7:0] S_mv_region_count;
    wire S_mv_regions_overflow;
    wire S_mv_global_change;
    wire [15:0] S_mv_r0_area;
    wire [7:0] S_mv_r0_xmin, S_mv_r0_xmax, S_mv_r0_ymin, S_mv_r0_ymax;
    wire [15:0] S_mv_r1_area,S_mv_r2_area,S_mv_r3_area;
    wire [7:0] S_mv_r1_xmin,S_mv_r1_xmax,S_mv_r1_ymin,S_mv_r1_ymax;
    wire [7:0] S_mv_r2_xmin,S_mv_r2_xmax,S_mv_r2_ymin,S_mv_r2_ymax;
    wire [7:0] S_mv_r3_xmin,S_mv_r3_xmax,S_mv_r3_ymin,S_mv_r3_ymax;
    // P5: the latency readout is covered per pixel by tb_frame_meta. This shell therefore forces
    // LAT_OSD=0 (see display_instance below) and ties the payload to "invalid"; cells 17..25 stay
    // blank and the status region keeps its 464-pixel width, so these TBs' expectations are
    // unchanged. Declared explicitly: otherwise the 16-bit port would attach to an implicit
    // 1-bit net.
    wire [15:0] S_lat_ms    = 16'd0;
    wire        S_lat_valid = 1'b0;
    wire        S_lat_tgl   = 1'b0;
    wire        S_out_first_tgl;
}
set adapter_instance [display_instance $top_source "    video_display_pipe #(" u_video_display_pipe]
if {![info exists display_calibration]} {
    regsub {\.CALIBRATION\s*\(\s*1\s*\)} $adapter_instance {.CALIBRATION(0)} adapter_instance
} else {
    if {![info exists display_width]} {set display_width 512}
    regsub {\.IMAGE_WIDTH\(1280\)} $adapter_instance ".IMAGE_WIDTH($display_width)" adapter_instance
    if {![info exists display_height]} {set display_height 256}
    regsub {\.V_ACTIVE\(720\)} $adapter_instance ".V_ACTIVE($display_height)" adapter_instance
}
if {![info exists display_spatial]} {
    regsub {\.SPATIAL_COLOR\(1\)} $adapter_instance {.SPATIAL_COLOR(0)} adapter_instance
    regsub {\.SHAPE_GEOMETRY\(1\)} $adapter_instance {.SHAPE_GEOMETRY(0)} adapter_instance
}
if {![info exists display_multitarget]} {regsub {\.MULTI_TARGET\(1\)} $adapter_instance {.MULTI_TARGET(0)} adapter_instance}
puts $shell $adapter_instance
set mixer_instance [display_instance $top_source "    hdmi_mixer #(" u_hdmi_mixer]
# P5: this shell disables the latency readout (covered per pixel by tb_frame_meta). Forcing the
# parameter here keeps the shell under the ModelSim Altera Starter statement limit; the extracted
# top-level parameter list would otherwise pull in the sampler and slow these runs down.
set lat_sub [regsub {\.LAT_OSD\s*\(\s*1\s*\)} $mixer_instance {.LAT_OSD ( 0 )} mixer_instance]
if {$lat_sub == 0} {
    # Fail fast: continuing would elaborate the P5 sampler in this shell (past the ModelSim Altera
    # Starter statement limit, slowing these regressions several-fold) and the resulting failure
    # would look like an unrelated testbench error.
    error "P5: LAT_OSD(1) not found in the extracted hdmi_mixer instance; update sim_p3_display.tcl"
}
if {![info exists display_calibration]} {
    regsub {\.READABLE_OSD\s*\(\s*1\s*\)} $mixer_instance {.READABLE_OSD(0)} mixer_instance
    regsub {\.CAL_OSD\s*\(\s*1\s*\)} $mixer_instance {.CAL_OSD(0)} mixer_instance
} else {
    regsub {\.IMG_WIDTH\s*\(\s*1280\s*\)} $mixer_instance ".IMG_WIDTH($display_width)" mixer_instance
    regsub {\.IMG_HEIGHT\s*\(\s*720\s*\)} $mixer_instance ".IMG_HEIGHT($display_height)" mixer_instance
}
if {![info exists display_spatial]} {regsub {\.CAL_MULTIPOINT\(1\)} $mixer_instance {.CAL_MULTIPOINT(0)} mixer_instance}
if {![info exists display_multitarget]} {regsub {\.MULTI_TARGET_OSD\(1\)} $mixer_instance {.MULTI_TARGET_OSD(0)} mixer_instance}
puts $shell $mixer_instance
if {[info exists display_status_cdc]} {puts $shell [display_instance $top_source "awb_status_cdc u_awb_status_cdc(" u_awb_status_cdc]}
puts $shell "endmodule"
close $shell
if {[info exists display_multitarget]} {
    set fd [open [file join $sim_dir p3_display_glue.v] r];set glue [read $fd];close $fd
    regsub {wire S_denoise_stable=1'b0;} $glue {} glue
    regsub {input \[7:0\] S_preproc_thresh,} $glue {input [7:0] S_preproc_thresh, input S_denoise_stable,} glue
    set fd [open [file join $sim_dir p3_display_glue.v] w];puts $fd $glue;close $fd
}
if {[info exists display_calibration]} {
    set fd [open [file join $sim_dir p3_display_glue.v] r];set glue [read $fd];close $fd
    regsub {wire S_cal_stable=1'b0,S_lock_stable=1'b0,S_awb_frozen=1'b0;} $glue {} glue
    regsub {input \[7:0\] S_preproc_thresh,} $glue {input [7:0] S_preproc_thresh,
    input S_cal_stable,S_lock_stable,S_awb_frozen,} glue
    set fd [open [file join $sim_dir p3_display_glue.v] w];puts $fd $glue;close $fd
}

if {[info exists display_status_cdc]} {
    set fd [open [file join $sim_dir p3_display_glue.v] r];set glue [read $fd];close $fd
    regsub {wire \[40:0\] S_awb_status=41'd0;} $glue {wire [40:0] S_awb_status; wire S_rst_n=S_hdmi_rst_n;} glue
    regsub {input \[7:0\] S_preproc_thresh,} $glue {input [7:0] S_preproc_thresh, input S_csi_rx_clk,S_awb_status_valid,input [40:0] S_awb_status_src,} glue
    set fd [open [file join $sim_dir p3_display_glue.v] w];puts $fd $glue;close $fd
}
vlog -work work [file join $root src rtl ctrl awb_status_cdc.v]
if {[catch {
vlog -work work [file join $root src rtl osd logo_indexed_rom.v]
vlog -work work [file join $root src rtl detect color_component.v] [file join $root src rtl detect color_scan_runs.v] [file join $root src rtl detect shape_labels.v] [file join $root src rtl detect shape_polygon.v] [file join $root src rtl detect color_multitarget.v] [file join $root src rtl osd color_target_osd.v]
vlog -work work +incdir+$root/src/rtl/isp [file join $root src rtl isp spatial_color.v]
vlog -work work [file join $root src rtl detect shape_edges.v]
vlog -work work [file join $root src rtl preproc shared_denoise.v]
# CAL0 does not elaborate these branches. Keep the CAL1 consumer entry intact.
if {[info exists display_calibration]} {
vlog -work work [file join $root src rtl osd calibration_osd.v] [file join $root src rtl ctrl color_sample.v] [file join $root src rtl ctrl color_regions.v] [file join $root src rtl osd color_regions_osd.v]
}
vlog -work work [file join $root src rtl preproc line_delay.v] \
    [file join $root src rtl preproc line_delay_eram.v] \
    [file join $root src rtl ctrl ae_stats.v] \
    [file join $root src rtl preproc rgb2ycbcr.v] \
    [file join $root src rtl preproc preproc_pipe.v] \
    [file join $root src rtl detect detect_shape.v] \
    [file join $root src rtl osd detect_osd.v] \
    [file join $root src rtl motion frame_store.v] \
    [file join $root src rtl motion motion_sample.v] \
    [file join $root src rtl motion motion_mask.v] \
    [file join $root src rtl motion motion_runs.v] \
    [file join $root src rtl motion motion_labels.v] \
    [file join $root src rtl osd motion_osd.v] \
    [file join $root src rtl top video_display_pipe.v] \
    [file join $hdl hdmi_mixer.v] [file join $hdl osd_char_lib.v] \
    [file join $hdl anlogic_logo_rom.v] [file join $sim_dir p3_display_glue.v] \
    [file join $root src sim ${display_tb}.v]
} failure]} {if {$is_batch} {quit -force -code 1}; error $failure}
if {![info exists display_vsim_args]} {set display_vsim_args {}}
eval vsim -voptargs=+acc $display_vsim_args work.$display_tb $eram_sim_top
onfinish stop
run $display_duration
set finished [examine -radix unsigned sim:/$display_tb/test_done]
set errors [examine -radix decimal sim:/$display_tb/errors]
if {$finished != 1 || $errors != 0} {
    if {$is_batch} {quit -force -code 1}
    error "P3 display integration failed or timed out"
}
if {$is_batch} {quit -force -code 0}
