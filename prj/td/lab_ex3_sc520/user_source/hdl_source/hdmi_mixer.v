module hdmi_mixer #(
    parameter H_OFFSET = 128,
    parameter V_OFFSET = 60,
    parameter IMG_WIDTH = 1280,
    parameter IMG_HEIGHT = 720,
    parameter integer DEBUG_MODE = 0,
    parameter integer STATUS_OSD = 0,
    // P5: enable the frame-latency readout cells (17..25). Default 0 so the existing display
    // testbenches keep their per-pixel expectations; the working top instantiates it with 1.
    parameter integer READABLE_OSD = 0,
    parameter integer CAL_OSD = 0,
    parameter integer CAL_MULTIPOINT = 0,
    parameter integer CAL_POINTS = 5,
    parameter integer MULTI_TARGET_OSD = 0,
    parameter integer LAT_OSD = 0
)(
    input wire        I_clk,
    input wire        I_rst_n,

    input wire        I_video_vsync,
    input wire        I_video_hsync,
    input wire        I_video_de,
    input wire        I_video_user,
    input wire        I_video_last,

    input wire[3:0]   I_debug_status,
    input wire I_denoise,
    input wire I_lock,I_wb_frozen,I_cal_enable,I_cal_valid,
    input wire [CAL_POINTS*24-1:0] I_cal_regions_in,I_cal_regions_out,
    input wire [CAL_POINTS*13-1:0] I_cal_regions_clip_in,I_cal_regions_clip_out,
    input wire I_cal_regions_valid,
    input wire [40:0] I_awb_status,
    input wire [23:0] I_cal_rgb,
    input wire [12:0] I_cal_clipped,
    input wire [2:0] I_det_reason,
    input wire [3:0] I_mode,
    input wire [7:0] I_thresh,

    // P3 detection result (frame-latched by detect_shape, source-raster coordinates).
    // Invalid results carry frame_id all ones and draw no overlay.
    input wire        I_det_valid,
    input wire [1:0]  I_det_cls,
    input wire [19:0] I_det_area,
    input wire [11:0] I_det_xmin,
    input wire [11:0] I_det_xmax,
    input wire [11:0] I_det_ymin,
    input wire [11:0] I_det_ymax,
    input wire I_targets_valid,I_targets_overflow,
    input wire [7:0] I_targets_count,
    input wire [11:0] I_targets_colors,I_targets_shapes,
    input wire [79:0] I_targets_areas,
    input wire [191:0] I_targets_boxes,
 // P4 region overlay: four boxes packed as {area[15:0],xmin,xmax,ymin,ymax} (source coords,
 // already compensated by the causal-window offset; motion_osd adds the display +2)
 input wire        I_mv_valid,
 // PQ: 1 = automatic exposure currently owns the sensor write path (drives the AUTO/MAN text)
 input wire        I_ae_src_auto,
 input wire [7:0]  I_mv_count,
 input wire        I_mv_overflow, I_mv_global_change,
 input wire [47:0] I_mv_r0,
 input wire [47:0] I_mv_r1,
 input wire [47:0] I_mv_r2,
 input wire [47:0] I_mv_r3,

    // P5: frame latency payload from frame_meta (ddr domain). The payload is stable for a whole
    // display frame except for a single-bit validity revocation; I_lat_tgl is the publish event.
    input wire [15:0] I_lat_ms,
    input wire        I_lat_valid,
    input wire        I_lat_tgl,

    output wire       O_video_rd_en,
    input wire[23:0]  I_video_rd_data,

    output reg        O_hdmi_vsync,
    output reg        O_hdmi_hsync,
    output reg        O_hdmi_de,
    output reg[23:0]  O_hdmi_data,
    // P5: toggles once per display frame at the first output pixel (measurement endpoint)
    output wire       O_out_first_tgl
);

    reg        S_video_vsync_1d;
    reg        S_video_vsync_2d;
    reg        S_video_hsync_1d;
    reg        S_video_hsync_2d;
    reg        S_video_de_1d;
    reg        S_video_de_2d;
    reg [23:0] S_video_data_1d;
    reg [23:0] S_video_data_2d;
    reg [11:0] S_x;
    reg [11:0] S_y;
    reg [11:0] S_x_1d;
    reg [11:0] S_x_2d;
    reg [11:0] S_y_1d;
    reg [11:0] S_y_2d;
    // P5: I_video_user delayed by the same two cycles as S_video_de_2d, so the first output
    // pixel of a frame becomes a clean single-cycle event in the output timing space.
    reg        S_video_user_1d;
    reg        S_video_user_2d;
    reg        S_out_first_tgl;
    reg wb_frozen_1,wb_frozen_2;
    always @(posedge I_clk or negedge I_rst_n)
        if(!I_rst_n) begin wb_frozen_1<=0;wb_frozen_2<=0;end
        else begin wb_frozen_1<=I_wb_frozen;wb_frozen_2<=wb_frozen_1;end
    wire cal_hit;wire [23:0] cal_color;
    generate if(CAL_OSD!=0 && CAL_MULTIPOINT!=0) begin : g_regions
        color_regions_osd #(.H_ACTIVE(IMG_WIDTH),.V_ACTIVE(IMG_HEIGHT),.POINTS(CAL_POINTS)) u_cal_osd(
            .clk(I_clk),.rst_n(I_rst_n),.frame_start(I_video_de && I_video_user),
            .de(S_video_de_2d),.x(S_x_2d),.y(S_y_2d),.lock_exposure(I_lock),.freeze_wb(wb_frozen_2),
            .enable(I_cal_enable),.sample_valid(I_cal_regions_valid),
            .mean_in(I_cal_regions_in),.mean_out(I_cal_regions_out),
            .awb_status(I_awb_status),.clip_in(I_cal_regions_clip_in),.clip_out(I_cal_regions_clip_out),
            .shape_w(I_det_valid?I_det_xmax-I_det_xmin+12'd1:12'd0),
            .shape_h(I_det_valid?I_det_ymax-I_det_ymin+12'd1:12'd0),.reason(I_det_reason),.hit(cal_hit),.color(cal_color));
    end else if(CAL_OSD!=0) begin : g_cal
        calibration_osd #(.X0(IMG_WIDTH/2-32),.Y0(IMG_HEIGHT/2-32)) u_cal_osd(.clk(I_clk),.rst_n(I_rst_n),.frame_start(I_video_de && I_video_user),
            .de(S_video_de_2d),.x(S_x_2d),.y(S_y_2d),.lock_exposure(I_lock),.freeze_wb(wb_frozen_2),
            .enable(I_cal_enable),.sample_valid(I_cal_valid),.mean_rgb(I_cal_rgb),.clip_count(I_cal_clipped),
            .shape_w(I_det_valid?I_det_xmax-I_det_xmin+12'd1:12'd0),
            .shape_h(I_det_valid?I_det_ymax-I_det_ymin+12'd1:12'd0),.reason(I_det_reason),.hit(cal_hit),.color(cal_color));
    end else begin assign cal_hit=0;assign cal_color=0;end endgenerate


    reg        S_osd_hit;
    reg [23:0] S_osd_color;
    reg [11:0] S_logo_x;
    reg [11:0] S_logo_y;
    reg [3:0]  S_char_idx;
    reg [2:0]  S_char_row;
    reg [2:0]  S_char_col;
    reg [4:0]  S_char_bits;
    reg        S_char_on;
    reg        S_logo_blue_on;
    reg        S_logo_red_on;
    reg [11:0] S_logo_tmp_y;
    reg [3:0]  S_logo_red_band;
    reg [11:0] S_logo_red_x_start;
    reg [11:0] S_logo_red_x_end;
    // Two synchronous ROM reads start at the raw tap and reach stage 2.
    wire [14:0] S_logo_addr;
    wire [11:0] logo_y_1d, logo_x_1d,logo_raw_x,logo_raw_y;
    wire [14:0] logo_y_ext, logo_x_ext;
    wire[24:0] S_logo_pixel;
    reg [31:0] S_frame_cnt;
    reg [11:0] S_dyn_x;
    reg [11:0] S_dyn_y;
    reg [3:0]  S_dyn_char;
    reg [2:0]  S_dyn_col;
    reg [2:0]  S_dyn_row;
    reg [4:0]  S_dyn_bits;
    reg        S_dyn_on;
    reg [3:0]  S_dyn_digit_idx;
    reg [11:0] S_dyn_digit_x;
    reg [6:0]  S_dyn_seg;
    reg [3:0]  S_cnt_d0;
    reg [3:0]  S_cnt_d1;
    reg [3:0]  S_cnt_d2;
    reg [3:0]  S_cnt_d3;
    reg [3:0]  S_cnt_d4;
    reg [3:0]  S_cnt_d5;
    reg [2:0]  S_lbl_row;
    reg [2:0]  S_lbl_col;
    reg [1:0]  S_lbl_idx;
    reg [4:0]  S_lbl_bits;
    reg [6:0]  S_lbl_local_x;
    reg [3:0]  S_dyn_dec_digit;
    reg [4:0]  S_cn_local_x;
    reg [4:0]  S_cn_local_y;
    reg [3:0]  S_cn_col;
    reg [3:0]  S_cn_row;
    reg [15:0] S_cn_row_bits;
    reg        S_cn_on;
    reg [9:0]  S_cn_scale_x;
    reg [9:0]  S_cn_scale_y;
    reg [7:0]  S_pf_char;
    reg [4:0]  S_pf_local_x;
    reg [4:0]  S_pf_local_y;
    reg [3:0]  S_pf_col;
    reg [3:0]  S_pf_row;
    wire [15:0] S_pf_row_bits;
    reg        S_pf_on;
    reg [9:0]  S_pf_scale_x;
    reg [9:0]  S_pf_scale_y;

    // Reuse the vendor glyph library: MODE:n TH:ddd, frame-latched status.
    reg [3:0] mode_status;
    reg [7:0] thresh_status;
    reg ae_status;
    reg denoise_status;
    reg S_ae_src_auto_1, S_ae_src_auto;
    always @(posedge I_clk or negedge I_rst_n)
        if(!I_rst_n) begin mode_status<=0;thresh_status<=96;ae_status<=1;denoise_status<=0;end
        else if(I_video_de && I_video_user) begin
            mode_status<=I_mode;thresh_status<=I_thresh;ae_status<=S_ae_src_auto;denoise_status<=I_denoise;
        end
    reg [19:0] th_bcd;
    reg [3:0] th_steps;
    reg [11:0] th_digits;
    reg [19:0] th_next;
    integer th_i;
    always @(*) begin
        th_next=th_bcd;
        for(th_i=8;th_i<20;th_i=th_i+4)
            if(th_next[th_i +: 4]>=5)th_next[th_i +: 4]=th_next[th_i +: 4]+3;
        th_next=th_next<<1;
    end
    always @(posedge I_clk or negedge I_rst_n)
        if(!I_rst_n)begin th_bcd<=0;th_steps<=0;th_digits<=12'h096;end
        else if(I_video_de && I_video_user)begin th_bcd<={12'd0,I_thresh};th_steps<=8;end
        else if(th_steps!=0)begin
            th_bcd<=th_next;th_steps<=th_steps-1'b1;
            if(th_steps==1)th_digits<=th_next[19:8];
        end
    function [3:0] scale24;
        input [4:0] v;
        begin case(v)
            5'd0: scale24=4'd0;
            5'd1: scale24=4'd0;
            5'd2: scale24=4'd1;
            5'd3: scale24=4'd2;
            5'd4: scale24=4'd2;
            5'd5: scale24=4'd3;
            5'd6: scale24=4'd4;
            5'd7: scale24=4'd4;
            5'd8: scale24=4'd5;
            5'd9: scale24=4'd6;
            5'd10: scale24=4'd6;
            5'd11: scale24=4'd7;
            5'd12: scale24=4'd8;
            5'd13: scale24=4'd8;
            5'd14: scale24=4'd9;
            5'd15: scale24=4'd10;
            5'd16: scale24=4'd10;
            5'd17: scale24=4'd11;
            5'd18: scale24=4'd12;
            5'd19: scale24=4'd12;
            5'd20: scale24=4'd13;
            5'd21: scale24=4'd14;
            5'd22: scale24=4'd14;
            5'd23: scale24=4'd15;
            5'd24: scale24=4'd0;
            5'd25: scale24=4'd0;
            5'd26: scale24=4'd1;
            5'd27: scale24=4'd2;
            5'd28: scale24=4'd2;
            5'd29: scale24=4'd3;
            5'd30: scale24=4'd4;
            5'd31: scale24=4'd4;
            default: scale24=4'd0;
        endcase end
    endfunction
    function [3:0] scale15;
        input [4:0] v;
        begin case(v)
            5'd0: scale15=4'd0;
            5'd1: scale15=4'd1;
            5'd2: scale15=4'd2;
            5'd3: scale15=4'd3;
            5'd4: scale15=4'd4;
            5'd5: scale15=4'd5;
            5'd6: scale15=4'd6;
            5'd7: scale15=4'd7;
            5'd8: scale15=4'd8;
            5'd9: scale15=4'd9;
            5'd10: scale15=4'd10;
            5'd11: scale15=4'd11;
            5'd12: scale15=4'd12;
            5'd13: scale15=4'd13;
            5'd14: scale15=4'd14;
            5'd15: scale15=4'd0;
            5'd16: scale15=4'd1;
            5'd17: scale15=4'd2;
            5'd18: scale15=4'd3;
            5'd19: scale15=4'd4;
            5'd20: scale15=4'd5;
            5'd21: scale15=4'd6;
            5'd22: scale15=4'd7;
            5'd23: scale15=4'd8;
            5'd24: scale15=4'd9;
            5'd25: scale15=4'd10;
            5'd26: scale15=4'd11;
            5'd27: scale15=4'd12;
            5'd28: scale15=4'd13;
            5'd29: scale15=4'd14;
            5'd30: scale15=4'd0;
            5'd31: scale15=4'd1;
            default: scale15=4'd0;
        endcase end
    endfunction
    wire [11:0] status_x=S_x_2d-12'd192;
    wire motion_line=READABLE_OSD && S_y_2d>=64 && S_y_2d<80;
    wire [11:0] status_y=motion_line ? S_y_2d-12'd64 : S_y_2d-12'd16;
    // P5 cell budget: cells 0..16 carry MODE/TH/state; the latency readout needs cells 17..25
    // ("LAT:dddMS") or 17..23 ("INVALID"). Cells are 16 px wide and indexed by status_x[8:4], so
    // the region must reach S_x_2d < 192 + 26*16 = 608 when LAT_OSD is on. With LAT_OSD off the
    // region and every new case behave exactly as before, so existing testbenches keep their
    // per-pixel expectations unchanged.
    localparam integer STATUS_XMAX = READABLE_OSD ? 736 : ((LAT_OSD != 0) ? 608 : 464);
    wire status_region=STATUS_OSD && S_video_de_2d &&
        S_x_2d>=192 && S_x_2d<STATUS_XMAX && ((S_y_2d>=16 && S_y_2d<32) || motion_line);
    // PQ: the AUTO/MAN mode bit is generated in the 24 MHz domain (ae_ctrl.auto_valid).
    // Two flops bring it into the pixel domain so the crossing ends at the first
    // synchroniser stage (that arrival is exempted in the .sdc); status_char, the glyph ROM
    // and the output mux then stay local logic. Without this the tool saw an 11-level path
    // from ae_ctrl/auto_valid into O_hdmi_data_reg with only a 0.653 ns budget (SWNS -7.348).
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_ae_src_auto_1 <= 1'b1;   // reset state = AUTO
            S_ae_src_auto   <= 1'b1;
        end else begin
            S_ae_src_auto_1 <= I_ae_src_auto;
            S_ae_src_auto   <= S_ae_src_auto_1;
        end
    end

    // -------- P5: latency readout (ddr -> pixel, held payload + event toggle) --------
    // Same crossing style as ae_ctrl: the payload is stable for a whole display frame, the event
    // bit gets four synchroniser stages, the payload two, so the payload has settled when the
    // event is detected. The value is latched on the event and shown from that pixel onwards.
    // The whole latency path (sampler + readout cells) collapses when the readout is disabled.
    // This matters beyond area: the display testbench shells instantiate this module through the
    // wiring extracted from the working top, and an always-elaborated path pushes them past the
    // ModelSim Altera Starter statement limit; threshold warnings must be recorded per run.
    // The delivered top sets LAT_OSD=1; the shells override it to 0 (see sim_p3_display.tcl) and
    // rely on tb_frame_meta for this feature.
    // Readout values produced by the sampler below. Declared at module scope so the character
    // block can reference them; with LAT_OSD=0 that block's constant select forces every latency
    // cell blank, so their undriven value never reaches the output.
    reg        lat_shown_vld;
    reg [3:0]  lat_h, lat_t, lat_o;

    // FIRST synchroniser stages stay at MODULE scope, outside the generate block: the .sdc must
    // name them, and TD cannot match registers that live inside a generate scope (it reports them
    // as u_hdmi_mixer/g_lat$lat_tgl_1_reg, which read_sdc does not resolve - measured with
    // USR-6001/USR-8159 on the 2026-10-03 P5 builds). Keeping only these three flops outside means
    // enabling them costs a handful of statements when LAT_OSD=0, while the .sdc objects have the
    // same plain form as the PQ precedent (u_ae_ctrl/ssum_1[*], u_ae_ctrl/tgl_1).
    reg [15:0] lat_ms_1;
    reg        lat_vld_1;
    reg        lat_tgl_1;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            lat_ms_1<=16'd0; lat_vld_1<=1'b0; lat_tgl_1<=1'b0;
        end else begin
            lat_ms_1  <= I_lat_ms;
            lat_vld_1 <= I_lat_valid;
            lat_tgl_1 <= I_lat_tgl;
        end
    end

    generate if (LAT_OSD != 0) begin : g_lat
    // Later event stages, stage two of the payload, and the double-dabble readout.
    reg        lat_tgl_2, lat_tgl_3, lat_tgl_4, lat_tgl_d;
    reg [15:0] lat_ms_2;
    reg        lat_vld_2;
    reg [15:0] lat_shown;
    // 20 ns bundled-data arrival is longer than one 13.333 ns pixel period. Four event
    // stages leave two periods for payload skew before consuming the two-stage data.
    wire       lat_evt = lat_tgl_4 ^ lat_tgl_d;

    // double-dabble: 10-bit binary -> three decimal digits in 10 steps, no divider
    reg [21:0] bcd_sr;
    reg [3:0]  bcd_cnt;
    reg        bcd_busy;
    wire [3:0] dd_h = (bcd_sr[21:18] >= 4'd5) ? (bcd_sr[21:18] + 4'd3) : bcd_sr[21:18];
    wire [3:0] dd_t = (bcd_sr[17:14] >= 4'd5) ? (bcd_sr[17:14] + 4'd3) : bcd_sr[17:14];
    wire [3:0] dd_o = (bcd_sr[13:10] >= 4'd5) ? (bcd_sr[13:10] + 4'd3) : bcd_sr[13:10];
    wire [21:0] bcd_next = {dd_h, dd_t, dd_o, bcd_sr[9:0]} << 1;

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            lat_tgl_2<=1'b0; lat_tgl_3<=1'b0; lat_tgl_4<=1'b0; lat_tgl_d<=1'b0;
            lat_ms_2<=16'd0; lat_vld_2<=1'b0;
            lat_shown<=16'd0; lat_shown_vld<=1'b0;
            bcd_sr<=22'd0; bcd_cnt<=4'd0; bcd_busy<=1'b0;
            lat_h<=4'd0; lat_t<=4'd0; lat_o<=4'd0;
        end else begin
            lat_tgl_2 <= lat_tgl_1;
            lat_tgl_3 <= lat_tgl_2;
            lat_tgl_4 <= lat_tgl_3;
            lat_tgl_d <= lat_tgl_4;
            lat_ms_2  <= lat_ms_1;
            lat_vld_2 <= lat_vld_1;
            // Safety revocation is a monotonic single-bit update without a new data event.
            // Only a later coherent publication can make the displayed reading valid again.
            if(!lat_vld_2) lat_shown_vld <= 1'b0;

            if(lat_evt) begin
                lat_shown     <= lat_ms_2;
                lat_shown_vld <= lat_vld_2;
                bcd_sr   <= {12'd0, (lat_ms_2 > 16'd999) ? 10'd999 : lat_ms_2[9:0]};
                bcd_cnt  <= 4'd10;
                bcd_busy <= 1'b1;
            end else if(bcd_busy) begin
                bcd_sr  <= bcd_next;
                bcd_cnt <= bcd_cnt - 4'd1;
                if(bcd_cnt == 4'd1) begin
                    bcd_busy <= 1'b0;
                    lat_h <= bcd_next[21:18];
                    lat_t <= bcd_next[17:14];
                    lat_o <= bcd_next[13:10];
                end
            end
        end
    end
    end
    endgenerate

    // Convert the held region count once per frame, outside the glyph path.
    reg [19:0] mv_bcd;
    reg [3:0] mv_steps;
    reg [11:0] mv_digits;
    wire [3:0] mv_h=mv_bcd[19:16]>=5 ? mv_bcd[19:16]+4'd3 : mv_bcd[19:16];
    wire [3:0] mv_t=mv_bcd[15:12]>=5 ? mv_bcd[15:12]+4'd3 : mv_bcd[15:12];
    wire [3:0] mv_o=mv_bcd[11:8]>=5 ? mv_bcd[11:8]+4'd3 : mv_bcd[11:8];
    wire [19:0] mv_next={mv_h,mv_t,mv_o,mv_bcd[7:0]}<<1;
    reg mv_v_status,mv_err_status,mv_global_status;
    reg mv_snapshot_due;
    always @(posedge I_clk or negedge I_rst_n)
        if(!I_rst_n) mv_snapshot_due<=0;
        else mv_snapshot_due<=I_video_de && I_video_user;
    generate if(READABLE_OSD) begin: g_readable_count
    always @(posedge I_clk or negedge I_rst_n)
        if(!I_rst_n) begin mv_bcd<=0;mv_steps<=0;mv_digits<=0;
            mv_v_status<=0;mv_err_status<=0;mv_global_status<=0;end
        else if(mv_snapshot_due) begin
            mv_bcd<={12'd0,I_mv_count};mv_steps<=8;
            mv_v_status<=I_mv_valid;mv_err_status<=I_mv_overflow;mv_global_status<=I_mv_global_change;
        end else if(mv_steps!=0) begin
            mv_bcd<=mv_next;mv_steps<=mv_steps-1'b1;
            if(mv_steps==1) mv_digits<=mv_next[19:8];
        end

    end endgenerate

    wire [7:0] motion_char;
    reg [7:0] status_char;
    always @(*) begin
        // status_x is 12 bits wide; indexing with [7:4] only reaches cells 0..15 (status_x
        // < 256 => x < 448) and silently wraps higher x back to cell 0, which made cell 16
        // (the 'O' of AUTO) unreachable. [8:4] addresses cells 0..31.
        case(status_x[9:4])
            0:status_char="M";1:status_char="O";2:status_char="D";3:status_char="E";
            4:status_char=":";5:status_char=8'h30+mode_status;
            7:status_char="T";8:status_char="H";9:status_char=":";
            10:status_char=8'h30+{4'd0,th_digits[11:8]};
            11:status_char=8'h30+{4'd0,th_digits[7:4]};
            12:status_char=8'h30+{4'd0,th_digits[3:0]};
            // PQ: automatic exposure state. Cells 13..16 show AUTO or MAN (the last cell is
            // blanked for MAN, which is only three letters). Glyphs A/U/T/O/M/N already exist
            // in osd_char_lib (ASCII indexed), so this needs no font work.
            13:status_char=ae_status ? "A" : "M";
            14:status_char=ae_status ? "U" : "A";
            15:status_char=ae_status ? "T" : "N";
            16:status_char=ae_status ? "O" : 8'h00;
            // P5: frame latency. Valid frames show "LAT:dddMS" (cells 17..25); frames whose
            // metadata is not trustworthy (not COMMITTED, or the slot generation changed between
            // the display snapshot and the output event) show "INVALID" (cells 17..23) instead of
            // a fabricated 0 ms. LAT_OSD is a parameter, so with the readout disabled every one of
            // these cells folds to blank and the display testbench shells keep their expectations.
            // (A generate-wrapped second always block was tried first: with LAT_OSD=0 ModelSim
            // left its output at X and the OR corrupted the whole status character.)
            17:status_char=LAT_OSD ? (lat_shown_vld ? "L" : "I") : 8'h00;
            18:status_char=LAT_OSD ? (lat_shown_vld ? "A" : "N") : 8'h00;
            19:status_char=LAT_OSD ? (lat_shown_vld ? "T" : "V") : 8'h00;
            20:status_char=LAT_OSD ? (lat_shown_vld ? ":" : "A") : 8'h00;
            21:status_char=LAT_OSD ? (lat_shown_vld ? (8'h30+lat_h) : "L") : 8'h00;
            22:status_char=LAT_OSD ? (lat_shown_vld ? (8'h30+lat_t) : "I") : 8'h00;
            23:status_char=LAT_OSD ? (lat_shown_vld ? (8'h30+lat_o) : "D") : 8'h00;
            24:status_char=LAT_OSD ? (lat_shown_vld ? "M" : 8'h00) : 8'h00;
            25:status_char=LAT_OSD ? (lat_shown_vld ? "S" : 8'h00) : 8'h00;
            27:status_char=READABLE_OSD ? "D" : 0;
            28:status_char=READABLE_OSD ? "N" : 0;
            29:status_char=READABLE_OSD ? ":" : 0;
            30:status_char=READABLE_OSD ? "O" : 0;
            31:status_char=READABLE_OSD ? (denoise_status ? "N" : "F") : 0;
            32:status_char=READABLE_OSD && !denoise_status ? "F" : 0;
            default:status_char=0;
        endcase
        if(motion_line) status_char=motion_char;
    end

    generate if(READABLE_OSD) begin: g_motion_chars
        reg [7:0] mv_char;
        always @(*) begin
            mv_char=0;
            case(status_x[9:4])
                0:mv_char="M";1:mv_char="O";2:mv_char="T";
                3:mv_char="I";4:mv_char="O";5:mv_char="N";6:mv_char=":";
                7:mv_char=mv_v_status && !mv_err_status && !mv_global_status ? "0"+mv_digits[11:8] : "-";
                8:mv_char=mv_v_status && !mv_err_status && !mv_global_status ? "0"+mv_digits[7:4] : "-";
                9:mv_char=mv_v_status && !mv_err_status && !mv_global_status ? "0"+mv_digits[3:0] : "-";
                11:mv_char=mv_err_status ? "I" : mv_global_status ? "G" : mv_v_status ? "R" : "W";
                12:mv_char=mv_err_status ? "N" : mv_global_status ? "L" : mv_v_status ? "E" : "A";
                13:mv_char=mv_err_status ? "V" : mv_global_status ? "O" : mv_v_status ? "G" : "I";
                14:mv_char=mv_err_status ? "A" : mv_global_status ? "B" : mv_v_status ? "I" : "T";
                15:mv_char=mv_err_status ? "L" : mv_global_status ? "A" : mv_v_status ? "O" : 0;
                16:mv_char=mv_err_status ? "I" : mv_global_status ? "L" : mv_v_status ? "N" : 0;
                17:mv_char=mv_err_status ? "D" : !mv_global_status && mv_v_status ? "S" : 0;
                default:mv_char=0;
            endcase
        end
        assign motion_char=mv_char;
    end else begin
        assign motion_char=8'd0;
    end endgenerate
    wire [15:0] status_bits;
    osd_char_lib u_status_chars(.I_char(status_char),.I_row(status_y[3:0]),.O_row_bits(status_bits));
    wire status_on=status_region && status_bits[15-status_x[3:0]];

    // P3 detection overlay: box + result text, in the same two-cycle-delayed display
    // coordinate space as the rest of the OSD. Priority (see docs/接口-算法挂载点.md):
    // status line > detection overlay > logo > frame counter.
    wire [15:0] mv_a0 = I_mv_r0[47:32];
wire [7:0]  mv_x0l = I_mv_r0[31:24], mv_x0h = I_mv_r0[23:16];
wire [7:0]  mv_y0l = I_mv_r0[15:8],  mv_y0h = I_mv_r0[7:0];
wire [15:0] mv_a1 = I_mv_r1[47:32];
wire [7:0]  mv_x1l = I_mv_r1[31:24], mv_x1h = I_mv_r1[23:16];
wire [7:0]  mv_y1l = I_mv_r1[15:8],  mv_y1h = I_mv_r1[7:0];
wire [15:0] mv_a2 = I_mv_r2[47:32];
wire [7:0]  mv_x2l = I_mv_r2[31:24], mv_x2h = I_mv_r2[23:16];
wire [7:0]  mv_y2l = I_mv_r2[15:8],  mv_y2h = I_mv_r2[7:0];
wire [15:0] mv_a3 = I_mv_r3[47:32];
wire [7:0]  mv_x3l = I_mv_r3[31:24], mv_x3h = I_mv_r3[23:16];
wire [7:0]  mv_y3l = I_mv_r3[15:8],  mv_y3h = I_mv_r3[7:0];
wire        mv_ov_valid;
wire [23:0] mv_ov_rgb;

// P4 region boxes / count bar. de_2d is tied high and the pixel is only used where the
// surrounding mux is already inside the active window, exactly like the other overlays.
motion_osd u_motion_osd (
    .clk(I_clk), .rst_n(I_rst_n), .de_2d(S_video_de_2d),
    .x_2d(S_x_2d), .y_2d(S_y_2d),
    .regions_valid(I_mv_valid), .region_count(I_mv_count),
    .regions_overflow(I_mv_overflow), .global_change(I_mv_global_change),
    .r0_area(mv_a0), .r0_xmin(mv_x0l), .r0_xmax(mv_x0h),
    .r0_ymin(mv_y0l), .r0_ymax(mv_y0h),
    .r1_area(mv_a1), .r1_xmin(mv_x1l), .r1_xmax(mv_x1h),
    .r1_ymin(mv_y1l), .r1_ymax(mv_y1h),
    .r2_area(mv_a2), .r2_xmin(mv_x2l), .r2_xmax(mv_x2h),
    .r2_ymin(mv_y2l), .r2_ymax(mv_y2h),
    .r3_area(mv_a3), .r3_xmin(mv_x3l), .r3_xmax(mv_x3h),
    .r3_ymin(mv_y3l), .r3_ymax(mv_y3h),
    .ov_valid(mv_ov_valid), .ov_rgb(mv_ov_rgb)
);

wire det_ov_valid;
    wire [23:0] det_ov_rgb;
    generate if(MULTI_TARGET_OSD!=0)begin:g_targets
    color_target_osd #(.H_ACTIVE(IMG_WIDTH),.V_ACTIVE(IMG_HEIGHT)) u_targets_osd(
        .clk(I_clk),.rst_n(I_rst_n),.frame_start(S_video_de_1d && S_x_1d==0 && S_y_1d==0),
        .de(S_video_de_2d),.x(S_x_2d),.y(S_y_2d),
        .valid(I_targets_valid),.overflow(I_targets_overflow),.target_count(I_targets_count),
        .colors(I_targets_colors),.shapes(I_targets_shapes),.areas(I_targets_areas),.boxes(I_targets_boxes),
        .ov_valid(det_ov_valid),.ov_rgb(det_ov_rgb));
    end else begin:g_single_target
    detect_osd #(.READABLE(READABLE_OSD)) u_det_osd (
        .clk        ( I_clk          ),
        .rst_n      ( I_rst_n        ),
        .x_2d       ( S_x_2d         ),
        .y_2d       ( S_y_2d         ),
        .de_2d      ( S_video_de_2d  ),
        .res_valid  ( I_det_valid    ),
        .res_cls    ( I_det_cls      ),
        .res_area   ( I_det_area     ),
        .res_xmin   ( I_det_xmin     ),
        .res_xmax   ( I_det_xmax     ),
        .res_ymin   ( I_det_ymin     ),
        .res_ymax   ( I_det_ymax     ),
        .ov_valid   ( det_ov_valid   ),
        .ov_rgb     ( det_ov_rgb     )
    );
    end endgenerate

    localparam LOGO_X = 12'd0;
    localparam LOGO_Y = 12'd0;
    localparam LOGO_W = 12'd160;
    localparam LOGO_H = 12'd160;

    localparam COLOR_LOGO_BLUE   = 24'h1f315c;
    localparam COLOR_LOGO_RED    = 24'hec1c2d;
    localparam COLOR_TEXT        = 24'h00e6ff;
    localparam DYN_OSD_X         = 12'd375;
    localparam DYN_OSD_Y         = 12'd120;
    localparam DYN_OSD_W         = 12'd200;
    localparam DYN_OSD_H         = 12'd24;
    localparam CN_Y_OFFSET       = 12'd2;
    localparam COLOR_DYN_TEXT    = 24'hfff200;
    localparam CHAR_AN           = 8'h80;
    localparam CHAR_LU           = 8'h81;
    localparam CHAR_C            = 8'h43;
    localparam CHAR_N            = 8'h4e;
    localparam CHAR_T            = 8'h54;
    localparam CHAR_0            = 8'h30;
    localparam CHAR_COLON        = 8'h3a;


    // 7-seg bit mapping: {a,b,c,d,e,f,g}


    // Minimal 16x16 Chinese bitmap rows for "an" and "lu".


    // Unified prefix character library (16x16 rows): an/lu/C/N/T/:

    assign O_video_rd_en = I_video_de;

    assign logo_raw_x=I_video_user?12'd0:S_x;
    assign logo_raw_y=I_video_user?12'd0:S_y;
    assign logo_y_1d = logo_raw_y - LOGO_Y;
    assign logo_x_1d = logo_raw_x - LOGO_X;
    assign logo_y_ext = {3'd0, logo_y_1d};
    assign logo_x_ext = {3'd0, logo_x_1d};
    assign S_logo_addr=I_rst_n && I_video_de && logo_raw_x>=LOGO_X && logo_raw_x<LOGO_X+LOGO_W &&
        logo_raw_y>=LOGO_Y && logo_raw_y<LOGO_Y+LOGO_H ?
        (logo_y_ext<<7)+(logo_y_ext<<5)+logo_x_ext : 15'd0;
    logo_indexed_rom u_anlogic_logo_rom(.clk(I_clk),.addr(S_logo_addr),.pixel(S_logo_pixel));

    osd_char_lib u_osd_char_lib(
        .I_char     ( S_pf_char     ),
        .I_row      ( S_pf_row      ),
        .O_row_bits ( S_pf_row_bits )
    );

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_x <= 12'd0;
            S_y <= 12'd0;
        end
        else if(I_video_user) begin
            S_x <= 12'd1;
            S_y <= 12'd0;
        end
        else if(I_video_de) begin
            if(I_video_last) begin
                S_x <= 12'd0;
                S_y <= S_y + 12'd1;
            end
            else begin
                S_x <= S_x + 12'd1;
            end
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_frame_cnt <= 32'd0;
            S_cnt_d0 <= 4'd0;
            S_cnt_d1 <= 4'd0;
            S_cnt_d2 <= 4'd0;
            S_cnt_d3 <= 4'd0;
            S_cnt_d4 <= 4'd0;
            S_cnt_d5 <= 4'd0;
        end
        else if(I_video_user) begin
            S_frame_cnt <= S_frame_cnt + 32'd1;
            if(S_cnt_d0 == 4'd9) begin
                S_cnt_d0 <= 4'd0;
                if(S_cnt_d1 == 4'd9) begin
                    S_cnt_d1 <= 4'd0;
                    if(S_cnt_d2 == 4'd9) begin
                        S_cnt_d2 <= 4'd0;
                        if(S_cnt_d3 == 4'd9) begin
                            S_cnt_d3 <= 4'd0;
                            if(S_cnt_d4 == 4'd9) begin
                                S_cnt_d4 <= 4'd0;
                                if(S_cnt_d5 == 4'd9)
                                    S_cnt_d5 <= 4'd0;
                                else
                                    S_cnt_d5 <= S_cnt_d5 + 4'd1;
                            end
                            else
                                S_cnt_d4 <= S_cnt_d4 + 4'd1;
                        end
                        else
                            S_cnt_d3 <= S_cnt_d3 + 4'd1;
                    end
                    else
                        S_cnt_d2 <= S_cnt_d2 + 4'd1;
                end
                else
                    S_cnt_d1 <= S_cnt_d1 + 4'd1;
            end
            else
                S_cnt_d0 <= S_cnt_d0 + 4'd1;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_x_1d <= 12'd0;
            S_x_2d <= 12'd0;
            S_y_1d <= 12'd0;
            S_y_2d <= 12'd0;
        end
        else begin
            S_x_1d <= I_video_user ? 12'd0 : S_x;
            S_x_2d <= S_x_1d;
            S_y_1d <= I_video_user ? 12'd0 : S_y;
            S_y_2d <= S_y_1d;
        end
    end

    always @(*) begin
        S_osd_hit   = 1'b0;
        S_osd_color = 24'd0;

        S_logo_x = 12'd0;
        S_logo_y = 12'd0;
        S_char_idx = 4'd0;
        S_char_row = 3'd0;
        S_char_col = 3'd0;
        S_char_bits = 5'd0;
        S_char_on = 1'b0;
        S_logo_blue_on = 1'b0;
        S_logo_red_on = 1'b0;
        S_logo_tmp_y = 12'd0;
        S_logo_red_band = 4'd0;
        S_logo_red_x_start = 12'd0;
        S_logo_red_x_end = 12'd0;
        S_dyn_x = 12'd0;
        S_dyn_y = 12'd0;
        S_dyn_char = 4'd0;
        S_dyn_col = 3'd0;
        S_dyn_row = 3'd0;
        S_dyn_bits = 5'd0;
        S_dyn_on = 1'b0;
        S_dyn_digit_idx = 4'd0;
        S_dyn_digit_x = 12'd0;
        S_dyn_seg = 7'd0;
        S_lbl_row = 3'd0;
        S_lbl_col = 3'd0;
        S_lbl_idx = 2'd0;
        S_lbl_bits = 5'd0;
        S_lbl_local_x = 7'd0;
        S_dyn_dec_digit = 4'd0;
        S_cn_local_x = 5'd0;
        S_cn_local_y = 5'd0;
        S_cn_col = 4'd0;
        S_cn_row = 4'd0;
        S_cn_row_bits = 16'd0;
        S_cn_on = 1'b0;
        S_cn_scale_x = 10'd0;
        S_cn_scale_y = 10'd0;
        S_pf_char = 8'd0;
        S_pf_local_x = 5'd0;
        S_pf_local_y = 5'd0;
        S_pf_col = 4'd0;
        S_pf_row = 4'd0;
        S_pf_on = 1'b0;
        S_pf_scale_x = 10'd0;
        S_pf_scale_y = 10'd0;

        if(S_video_de_2d) begin
            if((S_x_2d >= LOGO_X) && (S_x_2d < (LOGO_X + LOGO_W)) &&
               (S_y_2d >= LOGO_Y) && (S_y_2d < (LOGO_Y + LOGO_H))) begin
                S_logo_x = S_x_2d - LOGO_X;
                S_logo_y = S_y_2d - LOGO_Y;
                if(S_logo_pixel[24]) begin
                    S_osd_hit   = 1'b1;
                    S_osd_color = S_logo_pixel[23:0];
                end
            end

            if((!S_osd_hit) &&
               (S_x_2d >= DYN_OSD_X) && (S_x_2d < (DYN_OSD_X + DYN_OSD_W)) &&
               (S_y_2d >= DYN_OSD_Y) && (S_y_2d < (DYN_OSD_Y + DYN_OSD_H))) begin
                S_dyn_x = S_x_2d - DYN_OSD_X;
                S_dyn_y = S_y_2d - DYN_OSD_Y;

                // Unified prefix render using one character library.
                // an:[0..23], lu:[24..47], C:[52..67], N:[68..83], T:[84..99], :[100..107]
                if((S_dyn_x < 12'd108) && (S_dyn_y < 12'd24)) begin
                    if((S_dyn_x < 12'd24) || ((S_dyn_x >= 12'd24) && (S_dyn_x < 12'd48))) begin
                        if(S_dyn_y >= CN_Y_OFFSET)
                            S_pf_local_y = S_dyn_y - CN_Y_OFFSET;
                        else
                            S_pf_local_y = 5'd31;

                        if(S_dyn_x < 12'd24) begin
                            S_pf_char = CHAR_AN;
                            S_pf_local_x = S_dyn_x;
                        end
                        else begin
                            S_pf_char = CHAR_LU;
                            S_pf_local_x = S_dyn_x - 12'd24;
                        end

                        if((S_pf_local_x < 5'd24) && (S_pf_local_y < 5'd24)) begin
                            S_pf_scale_x = S_pf_local_x * 10'd16;
                            S_pf_scale_y = S_pf_local_y * 10'd16;
                            S_pf_col = scale24(S_pf_local_x);
                            S_pf_row = scale24(S_pf_local_y);
                            case(S_pf_col)
                                4'd0:  S_pf_on = S_pf_row_bits[15];
                                4'd1:  S_pf_on = S_pf_row_bits[14];
                                4'd2:  S_pf_on = S_pf_row_bits[13];
                                4'd3:  S_pf_on = S_pf_row_bits[12];
                                4'd4:  S_pf_on = S_pf_row_bits[11];
                                4'd5:  S_pf_on = S_pf_row_bits[10];
                                4'd6:  S_pf_on = S_pf_row_bits[9];
                                4'd7:  S_pf_on = S_pf_row_bits[8];
                                4'd8:  S_pf_on = S_pf_row_bits[7];
                                4'd9:  S_pf_on = S_pf_row_bits[6];
                                4'd10: S_pf_on = S_pf_row_bits[5];
                                4'd11: S_pf_on = S_pf_row_bits[4];
                                4'd12: S_pf_on = S_pf_row_bits[3];
                                4'd13: S_pf_on = S_pf_row_bits[2];
                                4'd14: S_pf_on = S_pf_row_bits[1];
                                4'd15: S_pf_on = S_pf_row_bits[0];
                                default: S_pf_on = 1'b0;
                            endcase
                        end
                    end
                    else if((S_dyn_x >= 12'd52) && (S_dyn_x < 12'd100) && (S_dyn_y >= 12'd4) && (S_dyn_y < 12'd20)) begin
                        if(S_dyn_x < 12'd68) begin
                            S_pf_char = CHAR_C;
                            S_pf_local_x = S_dyn_x - 12'd52;
                        end
                        else if(S_dyn_x < 12'd84) begin
                            S_pf_char = CHAR_N;
                            S_pf_local_x = S_dyn_x - 12'd68;
                        end
                        else begin
                            S_pf_char = CHAR_T;
                            S_pf_local_x = S_dyn_x - 12'd84;
                        end
                        S_pf_local_y = S_dyn_y - 12'd4;
                        S_pf_col = S_pf_local_x[3:0];
                        S_pf_row = S_pf_local_y[3:0];
                        case(S_pf_col)
                            4'd0:  S_pf_on = S_pf_row_bits[15];
                            4'd1:  S_pf_on = S_pf_row_bits[14];
                            4'd2:  S_pf_on = S_pf_row_bits[13];
                            4'd3:  S_pf_on = S_pf_row_bits[12];
                            4'd4:  S_pf_on = S_pf_row_bits[11];
                            4'd5:  S_pf_on = S_pf_row_bits[10];
                            4'd6:  S_pf_on = S_pf_row_bits[9];
                            4'd7:  S_pf_on = S_pf_row_bits[8];
                            4'd8:  S_pf_on = S_pf_row_bits[7];
                            4'd9:  S_pf_on = S_pf_row_bits[6];
                            4'd10: S_pf_on = S_pf_row_bits[5];
                            4'd11: S_pf_on = S_pf_row_bits[4];
                            4'd12: S_pf_on = S_pf_row_bits[3];
                            4'd13: S_pf_on = S_pf_row_bits[2];
                            4'd14: S_pf_on = S_pf_row_bits[1];
                            4'd15: S_pf_on = S_pf_row_bits[0];
                            default: S_pf_on = 1'b0;
                        endcase
                    end
                    else if((S_dyn_x >= 12'd100) && (S_dyn_x < 12'd108) && (S_dyn_y >= 12'd4) && (S_dyn_y < 12'd20)) begin
                        S_pf_char = CHAR_COLON;
                        S_pf_local_x = S_dyn_x - 12'd100;
                        S_pf_local_y = S_dyn_y - 12'd4;
                        S_pf_scale_x = S_pf_local_x * 10'd16;
                        S_pf_col = S_pf_scale_x / 10'd8;
                        S_pf_row = S_pf_local_y[3:0];
                        case(S_pf_col)
                            4'd0:  S_pf_on = S_pf_row_bits[15];
                            4'd1:  S_pf_on = S_pf_row_bits[14];
                            4'd2:  S_pf_on = S_pf_row_bits[13];
                            4'd3:  S_pf_on = S_pf_row_bits[12];
                            4'd4:  S_pf_on = S_pf_row_bits[11];
                            4'd5:  S_pf_on = S_pf_row_bits[10];
                            4'd6:  S_pf_on = S_pf_row_bits[9];
                            4'd7:  S_pf_on = S_pf_row_bits[8];
                            4'd8:  S_pf_on = S_pf_row_bits[7];
                            4'd9:  S_pf_on = S_pf_row_bits[6];
                            4'd10: S_pf_on = S_pf_row_bits[5];
                            4'd11: S_pf_on = S_pf_row_bits[4];
                            4'd12: S_pf_on = S_pf_row_bits[3];
                            4'd13: S_pf_on = S_pf_row_bits[2];
                            4'd14: S_pf_on = S_pf_row_bits[1];
                            4'd15: S_pf_on = S_pf_row_bits[0];
                            default: S_pf_on = 1'b0;
                        endcase
                    end

                    if(S_pf_on)
                        S_dyn_on = 1'b1;
                end

                // Decimal 6 digits starts at x=110. Each digit is 15x24.
                if((S_dyn_x >= 12'd110) && (S_dyn_x < 12'd200)) begin
                    if(S_dyn_x < 12'd125) begin
                        S_dyn_digit_idx = 4'd0;
                        S_dyn_digit_x = S_dyn_x - 12'd110;
                        S_dyn_dec_digit = S_cnt_d5;
                    end
                    else if(S_dyn_x < 12'd140) begin
                        S_dyn_digit_idx = 4'd1;
                        S_dyn_digit_x = S_dyn_x - 12'd125;
                        S_dyn_dec_digit = S_cnt_d4;
                    end
                    else if(S_dyn_x < 12'd155) begin
                        S_dyn_digit_idx = 4'd2;
                        S_dyn_digit_x = S_dyn_x - 12'd140;
                        S_dyn_dec_digit = S_cnt_d3;
                    end
                    else if(S_dyn_x < 12'd170) begin
                        S_dyn_digit_idx = 4'd3;
                        S_dyn_digit_x = S_dyn_x - 12'd155;
                        S_dyn_dec_digit = S_cnt_d2;
                    end
                    else if(S_dyn_x < 12'd185) begin
                        S_dyn_digit_idx = 4'd4;
                        S_dyn_digit_x = S_dyn_x - 12'd170;
                        S_dyn_dec_digit = S_cnt_d1;
                    end
                    else begin
                        S_dyn_digit_idx = 4'd5;
                        S_dyn_digit_x = S_dyn_x - 12'd185;
                        S_dyn_dec_digit = S_cnt_d0;
                    end

                    // Render decimal digits through unified 16x16 character library.
                    // Keep enlarged 15x24 box for readability.
                    if((S_dyn_digit_x < 12'd15) && (S_dyn_y < 12'd24)) begin
                        S_pf_char = CHAR_0 + {4'd0, S_dyn_dec_digit};
                        S_pf_local_x = S_dyn_digit_x[4:0];
                        S_pf_local_y = S_dyn_y[4:0];
                        S_pf_scale_x = S_pf_local_x * 10'd16;
                        S_pf_scale_y = S_pf_local_y * 10'd16;
                        S_pf_col = scale15(S_pf_local_x);
                        S_pf_row = scale24(S_pf_local_y);
                        case(S_pf_col)
                            4'd0:  S_pf_on = S_pf_row_bits[15];
                            4'd1:  S_pf_on = S_pf_row_bits[14];
                            4'd2:  S_pf_on = S_pf_row_bits[13];
                            4'd3:  S_pf_on = S_pf_row_bits[12];
                            4'd4:  S_pf_on = S_pf_row_bits[11];
                            4'd5:  S_pf_on = S_pf_row_bits[10];
                            4'd6:  S_pf_on = S_pf_row_bits[9];
                            4'd7:  S_pf_on = S_pf_row_bits[8];
                            4'd8:  S_pf_on = S_pf_row_bits[7];
                            4'd9:  S_pf_on = S_pf_row_bits[6];
                            4'd10: S_pf_on = S_pf_row_bits[5];
                            4'd11: S_pf_on = S_pf_row_bits[4];
                            4'd12: S_pf_on = S_pf_row_bits[3];
                            4'd13: S_pf_on = S_pf_row_bits[2];
                            4'd14: S_pf_on = S_pf_row_bits[1];
                            4'd15: S_pf_on = S_pf_row_bits[0];
                            default: S_pf_on = 1'b0;
                        endcase
                        if(S_pf_on)
                            S_dyn_on = 1'b1;
                    end
                end

                if(S_dyn_on) begin
                    S_osd_hit = 1'b1;
                    S_osd_color = COLOR_DYN_TEXT;
                end
            end
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_video_vsync_1d <= 1'b0;
            S_video_vsync_2d <= 1'b0;
            S_video_hsync_1d <= 1'b0;
            S_video_hsync_2d <= 1'b0;
            S_video_de_1d    <= 1'b0;
            S_video_de_2d    <= 1'b0;
            S_video_user_1d  <= 1'b0;
            S_video_user_2d  <= 1'b0;
            S_out_first_tgl  <= 1'b0;
            O_hdmi_vsync     <= 1'b0;
            O_hdmi_hsync     <= 1'b0;
            O_hdmi_de        <= 1'b0;
            O_hdmi_data      <= 24'd0;
        end
        else begin
            S_video_vsync_1d <= I_video_vsync;
            S_video_vsync_2d <= S_video_vsync_1d;
            O_hdmi_vsync     <= S_video_vsync_2d;

            S_video_hsync_1d <= I_video_hsync;
            S_video_hsync_2d <= S_video_hsync_1d;
            O_hdmi_hsync     <= S_video_hsync_2d;

            S_video_de_1d    <= I_video_de;
            S_video_de_2d    <= S_video_de_1d;
            O_hdmi_de        <= S_video_de_2d;
            // P5: single-cycle event at the first output pixel of each display frame (video_user
            // is a one-pixel pulse at the frame's first active pixel, see uivtc O_vtc_user).
            S_video_user_1d  <= I_video_user;
            S_video_user_2d  <= S_video_user_1d;
            if(S_video_de_2d && S_video_user_2d) S_out_first_tgl <= ~S_out_first_tgl;
            S_video_data_1d  <= I_video_rd_data;
            S_video_data_2d  <= S_video_data_1d;

            if(DEBUG_MODE == 1) begin
                if(S_video_de_2d) begin
                    if(S_x < 12'd128)
                        O_hdmi_data <= 24'hff0000;
                    else if(S_x < 12'd256)
                        O_hdmi_data <= 24'h00ff00;
                    else if(S_x < 12'd384)
                        O_hdmi_data <= 24'h0000ff;
                    else if(S_x < 12'd512)
                        O_hdmi_data <= 24'hffff00;
                    else if(S_x < 12'd640)
                        O_hdmi_data <= 24'h00ffff;
                    else if(S_x < 12'd768)
                        O_hdmi_data <= 24'hff00ff;
                    else if(S_x < 12'd896)
                        O_hdmi_data <= 24'hffffff;
                    else
                        O_hdmi_data <= 24'h202020;
                end
                else begin
                    O_hdmi_data <= 24'd0;
                end
            end
            else if(DEBUG_MODE == 2) begin
                if(S_video_de_2d) begin
                    case (I_debug_status)
                        4'b0000: O_hdmi_data <= 24'h000000;
                        4'b0001: O_hdmi_data <= 24'hff0000;
                        4'b0011: O_hdmi_data <= 24'hffff00;
                        4'b0111: O_hdmi_data <= 24'h00ff00;
                        4'b1111: O_hdmi_data <= I_video_rd_data;
                        default: O_hdmi_data <= 24'h0000ff;
                    endcase
                end
                else begin
                    O_hdmi_data <= 24'd0;
                end
            end
            else if(DEBUG_MODE == 3) begin
                if(S_video_de_2d) begin
                    if(S_x < 12'd256)
                        O_hdmi_data <= I_debug_status[0] ? 24'hff8000 : 24'h201000;
                    else if(S_x < 12'd512)
                        O_hdmi_data <= I_debug_status[1] ? 24'hffff00 : 24'h202000;
                    else if(S_x < 12'd768)
                        O_hdmi_data <= I_debug_status[2] ? 24'hff0000 : 24'h200000;
                    else
                        O_hdmi_data <= I_debug_status[3] ? 24'h00ffff : 24'h002020;
                end
                else begin
                    O_hdmi_data <= 24'd0;
                end
            end
            else begin
                if(status_on)
                    O_hdmi_data <= 24'hff0000;
                else if(cal_hit) O_hdmi_data<=cal_color;
                else if(READABLE_OSD && status_region)
                    O_hdmi_data <= 24'h101820;
                else if(det_ov_valid)
                    O_hdmi_data <= det_ov_rgb;
                else if(mv_ov_valid)
                    O_hdmi_data <= mv_ov_rgb;
                else if(S_osd_hit)
                    O_hdmi_data <= S_osd_color;
                else
                    O_hdmi_data <= S_video_data_2d;
            end
        end
    end

    // P5: measurement endpoint - toggles at the first output pixel of every display frame.
    assign O_out_first_tgl = S_out_first_tgl;

endmodule
