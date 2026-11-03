`timescale 1ns/1ps
// Complete frame-held payload crosses domains. The event has one more stage
// than the payload, allowing it to settle before use. Publications freeze busy.
module ae_ctrl #(
    parameter integer TARGET_HI=28800, DEADBAND_HI=1440,
    parameter integer RATE_DIV=4, REARM_FRAMES=300, AE_STEP=16,
    parameter integer AE_MIN=2, AE_MAX=1991, AG_MIN=16, AG_MAX=176,
    parameter integer CLIP_ENTER=9216, CLIP_EXIT=4608
)(
    input wire clk, rst_n,
    input wire [27:0] stats_sum,
    input wire [19:0] stats_clipped,
    input wire [1:0] stats_local_high,
    input wire hold_control,
    input wire stats_toggle, cfg_done,
    input wire manual_evt,     // synchronized held keys prevent re-arm
    input wire manual_toggle,  // pixel-domain short-press event
    input wire [10:0] cur_ae,
    input wire [7:0] cur_ag,
    output reg auto_valid,
    output reg [10:0] auto_ae,
    output reg [7:0] auto_ag,
    output wire auto_req,
    output reg [15:0] frame_cnt, silent_cnt
);
    reg tgl_1, tgl_2, tgl_3, tgl_d;
    reg mtgl_1, mtgl_2, mtgl_d;
    reg [27:0] ssum_1, ssum_2;
    reg [19:0] clip_1,clip_2;
    reg [1:0] local_1,local_2;
    reg hold_1,hold_2,highlight;
    wire hold_active=(hold_2===1'b1);
    wire frame_evt=tgl_3 ^ tgl_d;
    wire manual_input=manual_evt | (mtgl_2 ^ mtgl_d);
    wire [15:0] sum_hi=ssum_2[27:12];
    wire too_dark=sum_hi<TARGET_HI-DEADBAND_HI;
    wire too_bright=sum_hi>TARGET_HI+DEADBAND_HI;
    localparam integer RATE_W=RATE_DIV>1 ? $clog2(RATE_DIV) : 1;
    reg [RATE_W-1:0] rate_cnt;
    reg [10:0] work_ae;
    reg [7:0] work_ag;
    reg auto_valid_w;
    reg sent_valid;
    reg [10:0] sent_ae;
    reg [7:0] sent_ag;
    // Hold changed values pending through busy. The engine snapshots the same
    // published values on the edge accepting req while cfg_done is high.
    assign auto_req=!hold_active && auto_valid && (!sent_valid || auto_ae!=sent_ae || auto_ag!=sent_ag);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tgl_1<=0; tgl_2<=0; tgl_3<=0; tgl_d<=0;
            mtgl_1<=0; mtgl_2<=0; mtgl_d<=0; ssum_1<=0; ssum_2<=0;
            work_ae<=AE_MAX; work_ag<=AG_MIN; auto_ae<=AE_MAX; auto_ag<=AG_MIN;
            auto_valid<=1; auto_valid_w<=1;
            sent_valid<=0; sent_ae<=0; sent_ag<=0;
            rate_cnt<=0; frame_cnt<=0; silent_cnt<=0;
            clip_1<=0;clip_2<=0;local_1<=0;local_2<=0;hold_1<=0;hold_2<=0;highlight<=0;
        end else begin
            tgl_1<=stats_toggle; tgl_2<=tgl_1; tgl_3<=tgl_2; tgl_d<=tgl_3;
            ssum_1<=stats_sum; ssum_2<=ssum_1;
            clip_1<=stats_clipped;clip_2<=clip_1;hold_1<=hold_control;hold_2<=hold_1;
            case(stats_local_high)2'd1:local_1<=1;2'd2:local_1<=2;default:local_1<=0;endcase
            local_2<=local_1;
            mtgl_1<=manual_toggle; mtgl_2<=mtgl_1; mtgl_d<=mtgl_2;
            if (!auto_valid) sent_valid<=0;
            else if (cfg_done && auto_req) begin
                sent_valid<=1; sent_ae<=auto_ae; sent_ag<=auto_ag;
            end
            if (frame_evt) frame_cnt<=frame_cnt+1'b1;
            if(frame_evt) begin
                if(clip_2>=CLIP_ENTER || local_2==2) highlight<=1;
                else if(clip_2<=CLIP_EXIT && local_2==0) highlight<=0;
            end
            if(hold_active) begin
                // The sensor engine completes its immutable in-flight snapshot.
                // No new request is issued; rebase on that completed actual value.
                work_ae<=cur_ae;work_ag<=cur_ag;rate_cnt<=0;silent_cnt<=0;
            end else if (manual_input) begin
                auto_valid_w<=0; silent_cnt<=0; rate_cnt<=0;
                work_ae<=cur_ae; work_ag<=cur_ag;
            end else if (frame_evt) begin
                if (!auto_valid_w) begin
                    if (silent_cnt>=REARM_FRAMES-1) begin
                        auto_valid_w<=1; silent_cnt<=0; rate_cnt<=0;
                        work_ae<=cur_ae; work_ag<=cur_ag;
                    end else silent_cnt<=silent_cnt+1'b1;
                end else if (rate_cnt>=RATE_DIV-1) begin
                    rate_cnt<=0;
                    if (too_bright || clip_2>=CLIP_ENTER || local_2==2 || (highlight && (clip_2>CLIP_EXIT || local_2==1))) begin
                        // Spend exposure time before analogue gain. On a bright
                        // scene, remove amplification first instead of keeping
                        // the startup gain high while shortening the shutter.
                        if (work_ag>AG_MIN) work_ag<=work_ag-1'b1;
                        else if (work_ae>AE_MIN)
                            work_ae<=work_ae>AE_MIN+AE_STEP ? work_ae-AE_STEP : AE_MIN;
                    end else if (too_dark && clip_2<=CLIP_EXIT && local_2==0) begin
                        if (work_ae<AE_MAX)
                            work_ae<=work_ae<AE_MAX-AE_STEP ? work_ae+AE_STEP : AE_MAX;
                        else if (work_ag<AG_MAX) work_ag<=work_ag+1'b1;
                    end
                end else rate_cnt<=rate_cnt+1'b1;
            end
            if (cfg_done) begin
                auto_ae<=work_ae; auto_ag<=work_ag; auto_valid<=auto_valid_w;
            end
        end
    end
endmodule
