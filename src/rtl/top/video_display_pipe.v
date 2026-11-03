// Adapter between the lab_ex3 DDR read-back port and the preprocessing pipeline.
//
// Two sampling stages from the read request to RGB, exactly as before: the FIFO
// request must always use the ORIGINAL VTC DE, never a delayed one, so read_en is
// the undelayed request_timing[2] (an AGENTS.md rule, unchanged here).
//
// The algorithm is now preproc_pipe (YCbCr + 3x3 window + Sobel / threshold /
// morphology / cartoon / chroma view). MODE and SPLIT_EN remain compile-time
// parameters so the previous fixed-function bitstreams can still be built, while
// i_mode/i_thresh allow runtime switching from btn_mode_ctrl:
//
//   i_use_btn = 0 -> mode = MODE parameter        (fixed-function, default)
//   i_use_btn = 1 -> mode = i_mode                (button switching)
//
// i_mode/i_thresh are only sampled by preproc_pipe at a frame start, so a switch
// can never tear a frame.
//
// Split-screen debug is preserved: SPLIT_EN = 1 shows the left half raw and the
// right half of the selected mode, both taken from the SAME delayed pixel stream.
module video_display_pipe #(
    parameter integer IMAGE_WIDTH = 1280,
    parameter integer V_ACTIVE = 720,
    parameter integer MODE = 0,          // 0 raw 1 gray 2 sobel 3 bin 4 open 5 cartoon 6 ycbcr
    parameter integer SPLIT_EN = 0,      // 1 = left half raw / right half algorithm
    parameter integer CALIBRATION = 0,
    parameter integer CAL_POINTS = 5,
    parameter integer SPATIAL_COLOR = 0,
    parameter integer SHAPE_GEOMETRY = 0,
    parameter integer MULTI_TARGET = 0
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [23:0] read_rgb,
    input  wire [4:0]  request_timing,   // undelayed VTC: {vsync,hsync,de,user,last}
    input  wire [3:0]  i_mode,           // runtime mode (from btn_mode_ctrl)
    input  wire [7:0]  i_thresh,         // runtime threshold preset
    input  wire        i_denoise,
    input wire i_cal_enable,
    output wire [23:0] cal_rgb,
    output wire [12:0] cal_clipped,
    output wire cal_valid,
    output wire [CAL_POINTS*24-1:0] cal_regions_in,cal_regions_out,
    output wire [CAL_POINTS*13-1:0] cal_regions_clip_in,cal_regions_clip_out,
    output wire cal_regions_valid,
    output wire [2:0] det_reason,
    output wire targets_valid,targets_overflow,
    output wire [7:0] targets_count,
    output wire [11:0] targets_colors,targets_shapes,
    output wire [79:0] targets_areas,
    output wire [191:0] targets_boxes,
    output wire [19:0] ae_clipped,
    output wire [1:0] ae_local_high,
    output wire        active_denoise,
    input  wire        i_use_btn,        // 1 = use i_mode/i_thresh
    output wire        read_en,
    output wire [23:0] rgb_out,
    output wire [3:0] active_mode,
    output wire [7:0] active_thresh,
    output wire [4:0]  timing_out,
    // P3 detection result (frame-latched, source-raster coordinates)
    output wire        det_valid,
    output wire [1:0]  det_cls,
    output wire [19:0] det_area,
    output wire [11:0] det_xmin,
    output wire [11:0] det_xmax,
    output wire [11:0] det_ymin,
    output wire [11:0] det_ymax,
    // PQ stage 1: per-frame luma statistics, taken at the same tap as P3/P4
    // (read_rgb + timing_2). Captured at the frame-start marker, published with a
    // one-cycle strobe plus an event bit; the controller waits for a stable payload.
    output wire [27:0] ae_sum,
    output wire [19:0] ae_n,
    output wire        ae_toggle,
    output wire        ae_valid
);
    reg [4:0] timing_1, timing_2;

    // Never feed delayed DE back into the FIFO request path.
    assign read_en = request_timing[2];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timing_1 <= 5'd0;
            timing_2 <= 5'd0;
        end else begin
            timing_1 <= request_timing;
            timing_2 <= timing_1;
        end
    end

    wire [3:0] mode_sel   = i_use_btn ? i_mode   : MODE[3:0];
    wire [7:0] thresh_sel = i_use_btn ? i_thresh : 8'd96;

    // Fixed, neutral-preserving Q8 matrix from the locked screen calibration.
    // Rows sum to 256: greys and the automatic white point remain unchanged.
    // Signed products fit 18 bits, including the largest positive row sum.
    wire signed [17:0] color_r={10'd0,read_rgb[23:16]};
    wire signed [17:0] color_g={10'd0,read_rgb[15:8]};
    wire signed [17:0] color_b={10'd0,read_rgb[7:0]};
    wire signed [17:0] delta_r=color_r-color_g,delta_b=color_b-color_g;
    reg signed [17:0] dr30,dr25,dr9,db25,db2,db47,base_r,base_g,base_b;
    reg [23:0] color_rgb;
    reg [4:0] color_timing_1,color_timing;
    function [7:0] matrix_clip;
        input signed [17:0] value;
        reg signed [18:0] rounded;
        begin
            rounded={value[17],value}+19'sd128;
            matrix_clip=rounded<0 ? 8'd0 : rounded>=19'sd65536 ? 8'd255 : rounded[15:8];
        end
    endfunction
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            {dr30,dr25,dr9,db25,db2,db47,base_r,base_g,base_b,color_rgb,color_timing_1,color_timing}<=0;
        end else begin
            dr30<=(delta_r<<5)-(delta_r<<1);
            dr25<=(delta_r<<4)+(delta_r<<3)+delta_r;
            dr9<=(delta_r<<3)+delta_r;
            db25<=(delta_b<<4)+(delta_b<<3)+delta_b;
            db2<=delta_b<<1;
            db47<=(delta_b<<5)+(delta_b<<4)-delta_b;
            {base_r,base_g,base_b}<={color_r<<8,color_g<<8,color_b<<8};
            {color_rgb,color_timing_1,color_timing}<=
                {{matrix_clip(base_r+dr30+db25),matrix_clip(base_g-dr25-db2),matrix_clip(base_b+dr9+db47)},timing_2,color_timing_1};
        end
    end

    wire [23:0] spatial_rgb,spatial_input;
    wire [4:0] spatial_timing;
    generate if(SPATIAL_COLOR!=0) begin : g_spatial
        spatial_color u_spatial(.clk(clk),.rst_n(rst_n),.rgb_in(color_rgb),.timing_in(color_timing),
            .rgb_out(spatial_rgb),.input_aligned(spatial_input),.timing_out(spatial_timing));
    end else begin
        assign spatial_rgb=color_rgb;assign spatial_input=color_rgb;assign spatial_timing=color_timing;
    end endgenerate
    wire [23:0] quality_rgb;
    wire [4:0] quality_timing;
    wire quality_restart;
    shared_denoise #(.IMAGE_WIDTH(IMAGE_WIDTH)) u_quality (
        .clk(clk),.rst_n(rst_n),.rgb_in(spatial_rgb),.timing_in(spatial_timing),
        .enable(i_denoise),.rgb_out(quality_rgb),.timing_out(quality_timing),
        .active_enable(active_denoise),.restart(quality_restart)
    );
    // Reset all P3/P4 state before the first pixel of the changed frame arrives.
    wire detect_rst_n=rst_n && !quality_restart;
    // With no vertical blanking the old filter tail can emerge after restart.
    // Ignore orphan pixels until the changed quality frame's own first marker.
    reg detect_armed;
    always @(posedge clk or negedge detect_rst_n)
        if(!detect_rst_n) detect_armed<=0;
        else if(quality_timing[2] && quality_timing[1]) detect_armed<=1;
    wire detect_de=quality_timing[2] && (detect_armed || quality_timing[1]);

    preproc_pipe #(.IMAGE_WIDTH(IMAGE_WIDTH)) u_preproc (
        .clk(clk),
        .rst_n(rst_n),
        .rgb_in(quality_rgb),
        .timing_in(quality_timing),
        .mode(mode_sel),
        .thresh(thresh_sel),
        .split_en(SPLIT_EN != 0),
        .rgb_out(rgb_out),
        .timing_out(timing_out), .active_mode(active_mode), .active_thresh(active_thresh)
    );

    // P3 detection branch. It taps the shared quality stream, aligned
    // with quality_timing, before mode processing: changing the display mode or
    // style must not change what is detected, and the image-quality stage needs the
    // untouched source as well. de/user/last come from the same aligned timing.
    generate if(MULTI_TARGET!=0)begin:g_multitarget
    color_multitarget #(.H_ACTIVE(IMAGE_WIDTH),.V_ACTIVE(V_ACTIVE)) u_targets(
        .clk(clk),.rst_n(detect_rst_n),.rgb(quality_rgb),
        .timing({quality_timing[4:3],detect_de,quality_timing[1:0]}),
        .valid(targets_valid),.overflow(targets_overflow),.target_count(targets_count),
        .colors(targets_colors),.shapes(targets_shapes),.areas(targets_areas),.boxes(targets_boxes));
    assign det_valid=targets_valid && targets_areas[19:0]!=0;
    assign det_cls=!det_valid?2'd0:targets_shapes[2:0]==1?2'd1:targets_shapes[2:0]==2?2'd2:2'd3;
    assign det_area=targets_areas[19:0];
    assign {det_xmin,det_xmax,det_ymin,det_ymax}=targets_boxes[47:0];
    assign det_reason=targets_overflow?3'd5:3'd0;
    end else begin:g_single_target
    assign targets_valid=0;assign targets_overflow=0;assign targets_count=0;
    assign targets_colors=0;assign targets_shapes=0;assign targets_areas=0;assign targets_boxes=0;
    detect_shape #(.H_ACTIVE(IMAGE_WIDTH), .V_ACTIVE(V_ACTIVE),.TRACK_BOX(1),.GEOMETRY(SHAPE_GEOMETRY)) u_detect (
        .clk(clk),
        .rst_n(detect_rst_n),
        .rgb_in(quality_rgb),
        .de(detect_de),
        .user(quality_timing[1]),
        .last(quality_timing[0]),
        .res_valid(det_valid),
        .res_cls(det_cls),
        .res_area(det_area),
        .res_xmin(det_xmin),
        .res_xmax(det_xmax),
        .res_ymin(det_ymin),
        .res_ymax(det_ymax),
        .res_reason(det_reason),.res_frame_id()
    );
    end endgenerate

    // PQ stage 1: luma sum/count over the active pixels of each frame, on the raw stream
    // already aligned with timing_2 (de=bit2, user=bit1). Purely additive: it observes the
    // stream and changes nothing in the display path.
    generate if(CALIBRATION!=0) begin : g_sample
    color_regions #(.H_ACTIVE(IMAGE_WIDTH),.V_ACTIVE(V_ACTIVE),.POINTS(CAL_POINTS)) u_regions(
        .clk(clk),.rst_n(rst_n),.enable(i_cal_enable),.timing(spatial_timing),
        .rgb_in(spatial_input),.rgb_out(spatial_rgb),.mean_in(cal_regions_in),.mean_out(cal_regions_out),
        .clip_in(cal_regions_clip_in),.clip_out(cal_regions_clip_out),.valid(cal_regions_valid));
    color_sample #(.H_ACTIVE(IMAGE_WIDTH),.V_ACTIVE(V_ACTIVE)) u_color_sample(
        .clk(clk),.rst_n(rst_n),.de(timing_2[2]),.user(timing_2[1]),.last(timing_2[0]),
        .enable(i_cal_enable),.rgb(read_rgb),.mean_rgb(cal_rgb),.clip_count(cal_clipped),.valid(cal_valid));
    end else begin assign cal_rgb=0;assign cal_clipped=0;assign cal_valid=0;
        assign cal_regions_in=0;assign cal_regions_out=0;assign cal_regions_clip_in=0;assign cal_regions_clip_out=0;assign cal_regions_valid=0;
    end endgenerate
    ae_stats #(.H_ACTIVE(IMAGE_WIDTH), .V_ACTIVE(V_ACTIVE)) u_ae_stats (
        .clk(clk),
        .rst_n(rst_n),
        .de(timing_2[2]),
        .user(timing_2[1]),
        .rgb(read_rgb),
        .stats_sum(ae_sum),
        .stats_n(ae_n),.stats_clipped(ae_clipped),.stats_local_high(ae_local_high),
        .stats_toggle(ae_toggle),
        .stats_valid(ae_valid)
    );
endmodule
