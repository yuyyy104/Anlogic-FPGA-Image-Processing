`timescale 1ns/1ps
// Fixed 64x64 central patch, four complete display frames. No image storage.
module color_sample #(
    parameter H_ACTIVE=1280,V_ACTIVE=720,
    parameter X0=H_ACTIVE/2-32,Y0=V_ACTIVE/2-32
)(
    input clk,rst_n,de,user,last,enable,
    input [23:0] rgb,
    output reg [23:0] mean_rgb,
    output reg [12:0] clip_count,
    output reg valid
);
    reg [11:0] col,row;
    wire [11:0] x=user?0:col,y=user?0:row;
    wire inside_patch=x>=X0 && x<X0+64 && y>=Y0 && y<Y0+64;
    wire clipped=rgb[23:16]>=250 || rgb[15:8]>=250 || rgb[7:0]>=250;
    reg active,started;
    reg [19:0] nr,sr,sg,sb;
    reg [12:0] count,nc;
    reg [21:0] tr,tg,tb;
    reg [14:0] tc;
    reg [1:0] frames;
    wire [21:0] total_r=tr+{2'b0,sr},total_g=tg+{2'b0,sg},total_b=tb+{2'b0,sb};
    wire [14:0] total_c=tc+{2'b0,nc};
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            col<=0;row<=0;active<=0;started<=0;nr<=0;sr<=0;sg<=0;sb<=0;count<=0;nc<=0;
            tr<=0;tg<=0;tb<=0;tc<=0;frames<=0;valid<=0;mean_rgb<=0;clip_count<=0;
        end else begin
            if(de) begin col<=last?0:x+1'b1;row<=last?y+1'b1:y;end
            if(de && user) begin
                active<=(enable===1'b1);started<=1;nr<=1;
                sr<=0;sg<=0;sb<=0;count<=0;nc<=0;
                // Production X0/Y0 are positive, so first pixel is outside.
                if(!enable || !active || !started || nr!=H_ACTIVE*V_ACTIVE || count!=4096) begin
                    frames<=0;tr<=0;tg<=0;tb<=0;tc<=0;valid<=0;
                end else if(frames==3) begin
                    mean_rgb<={total_r[21:14],total_g[21:14],total_b[21:14]};
                    clip_count<=total_c[14:2];valid<=1;frames<=0;tr<=0;tg<=0;tb<=0;tc<=0;
                end else begin
                    tr<=total_r;tg<=total_g;tb<=total_b;tc<=total_c;frames<=frames+1'b1;
                end
            end else if(de && started && nr<H_ACTIVE*V_ACTIVE+1) begin
                nr<=nr+1'b1;
                if(active && inside_patch) begin
                    count<=count+1'b1;
                    sr<=sr+rgb[23:16];sg<=sg+rgb[15:8];sb<=sb+rgb[7:0];
                    if(clipped) nc<=nc+1'b1;
                end
            end
        end
    end
endmodule
