// Two active-low user keys: mode and threshold.
// Each debounced press produces one action; release rearms the key, with no repeat.
// KEY3 and KEY4 are intentionally ignored; camera gain is automatic only.
`timescale 1ns/1ps
module btn_mode_ctrl #(
    parameter integer CLK_HZ=75000000,
    parameter integer DEB_MS=20
)(
    input wire clk,rst_n,
    input wire [3:0] i_btn,
    output reg [3:0] o_mode,
    output reg [7:0] o_thresh
);
    localparam integer MS_DIV=CLK_HZ/1000;
    function [7:0] thr_preset;
        input [2:0] idx;
        begin
            case(idx)
                0:thr_preset=32;1:thr_preset=64;2:thr_preset=96;3:thr_preset=128;
                4:thr_preset=160;5:thr_preset=192;6:thr_preset=224;default:thr_preset=240;
            endcase
        end
    endfunction
    reg [3:0] sync0=4'b1111,sync1=4'b1111;
    always @(posedge clk) begin sync0<=i_btn;sync1<=sync0;end
    wire [1:0] pressed=~sync1[1:0];
    reg [31:0] ms_cnt=0;
    reg ms_tick=0;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin ms_cnt<=0;ms_tick<=0;end
        else if(ms_cnt>=MS_DIV-1) begin ms_cnt<=0;ms_tick<=1;end
        else begin ms_cnt<=ms_cnt+1;ms_tick<=0;end
    end
    reg [15:0] deb[0:1];
    reg [1:0] held=0,armed=0,press_evt=0;
    reg [2:0] thr_idx=2;
    integer k;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            for(k=0;k<2;k=k+1) deb[k]<=0;
            held<=0;armed<=0;press_evt<=0;thr_idx<=2;
            o_mode<=0;o_thresh<=96;
        end else begin
            press_evt<=0;
            if(ms_tick) begin
                for(k=0;k<2;k=k+1) begin
                    if(pressed[k]!=held[k]) begin
                        if(deb[k]>=DEB_MS-1) begin
                            deb[k]<=0;held[k]<=pressed[k];
                            if(pressed[k] && armed[k]) begin
                                press_evt[k]<=1;armed[k]<=0;
                            end else if(!pressed[k]) armed[k]<=1;
                        end else deb[k]<=deb[k]+1;
                    end else begin
                        deb[k]<=0;
                        if(!held[k]) armed[k]<=1;
                    end
                end
            end
            if(press_evt[0]) o_mode<=(o_mode==6)?0:(o_mode==3)?5:o_mode+1'b1;
            if(press_evt[1]) thr_idx<=thr_idx+1'b1;
            o_thresh<=thr_preset(thr_idx);
        end
    end
endmodule
