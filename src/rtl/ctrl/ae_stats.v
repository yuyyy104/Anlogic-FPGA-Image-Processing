`timescale 1ns/1ps
// Raw display luma before preprocessing/OSD. de && user includes the first
// pixel. Reject reset fragments and wrong-sized frames; hold complete payloads.
module ae_stats #(
    parameter integer H_ACTIVE=1280, V_ACTIVE=720
)(
    input wire clk, rst_n, de, user,
    input wire [23:0] rgb,
    output reg [27:0] stats_sum,
    output reg [19:0] stats_n,
    output reg stats_toggle, stats_valid,
    output reg [19:0] stats_clipped,
    output reg [1:0] stats_local_high
);
    localparam integer PIXELS=H_ACTIVE*V_ACTIVE;
    wire [15:0] r={8'd0,rgb[23:16]}, g={8'd0,rgb[15:8]}, b={8'd0,rgb[7:0]};
    wire [15:0] ysum=(r<<6)+(r<<3)+(r<<2)+r+
        (g<<7)+(g<<4)+(g<<2)+(g<<1)+(b<<5)-(b<<2)+b+16'd128;
    wire [7:0] yv=ysum[15:8];
    reg [27:0] sum_r;
    reg [19:0] n_r;
    reg started;
    reg [19:0] clipped;
    wire clip_pixel=rgb[23:16]>=250 || rgb[15:8]>=250 || rgb[7:0]>=250;
    localparam TILE_MAX=((H_ACTIVE+2)/3)*((V_ACTIVE+2)/3);
    localparam TILE_W=$clog2(TILE_MAX+1)>0?$clog2(TILE_MAX+1):1;
    reg [11:0] col,row;
    wire [11:0] x=user?12'd0:col,y=user?12'd0:row;
    wire [1:0] tx=x<H_ACTIVE/3?0:x<(H_ACTIVE*2)/3?1:2;
    wire [1:0] ty=y<V_ACTIVE/3?0:y<(V_ACTIVE*2)/3?1:2;
    wire [3:0] tile=ty*3+tx;
    reg [TILE_W-1:0] tile_high[0:8];
    wire [TILE_W-1:0] tile_next=tile_high[tile]+1'b1;
    wire near_high=rgb[23:16]>=240 || rgb[15:8]>=240 || rgb[7:0]>=240;
    reg local_enter,local_exit;
    reg [TILE_W-1:0] enter_count,exit_count;
    integer k;
    always @(*)begin
        enter_count=1;exit_count=1;
        case(tile)
            4'd0:begin enter_count=(((H_ACTIVE/3)*(V_ACTIVE/3))+31)/32;exit_count=(((H_ACTIVE/3)*(V_ACTIVE/3))+63)/64;end
            4'd1:begin enter_count=((((H_ACTIVE*2)/3-H_ACTIVE/3)*(V_ACTIVE/3))+31)/32;exit_count=((((H_ACTIVE*2)/3-H_ACTIVE/3)*(V_ACTIVE/3))+63)/64;end
            4'd2:begin enter_count=(((H_ACTIVE-(H_ACTIVE*2)/3)*(V_ACTIVE/3))+31)/32;exit_count=(((H_ACTIVE-(H_ACTIVE*2)/3)*(V_ACTIVE/3))+63)/64;end
            4'd3:begin enter_count=(((H_ACTIVE/3)*((V_ACTIVE*2)/3-V_ACTIVE/3))+31)/32;exit_count=(((H_ACTIVE/3)*((V_ACTIVE*2)/3-V_ACTIVE/3))+63)/64;end
            4'd4:begin enter_count=((((H_ACTIVE*2)/3-H_ACTIVE/3)*((V_ACTIVE*2)/3-V_ACTIVE/3))+31)/32;exit_count=((((H_ACTIVE*2)/3-H_ACTIVE/3)*((V_ACTIVE*2)/3-V_ACTIVE/3))+63)/64;end
            4'd5:begin enter_count=(((H_ACTIVE-(H_ACTIVE*2)/3)*((V_ACTIVE*2)/3-V_ACTIVE/3))+31)/32;exit_count=(((H_ACTIVE-(H_ACTIVE*2)/3)*((V_ACTIVE*2)/3-V_ACTIVE/3))+63)/64;end
            4'd6:begin enter_count=(((H_ACTIVE/3)*(V_ACTIVE-(V_ACTIVE*2)/3))+31)/32;exit_count=(((H_ACTIVE/3)*(V_ACTIVE-(V_ACTIVE*2)/3))+63)/64;end
            4'd7:begin enter_count=((((H_ACTIVE*2)/3-H_ACTIVE/3)*(V_ACTIVE-(V_ACTIVE*2)/3))+31)/32;exit_count=((((H_ACTIVE*2)/3-H_ACTIVE/3)*(V_ACTIVE-(V_ACTIVE*2)/3))+63)/64;end
            4'd8:begin enter_count=(((H_ACTIVE-(H_ACTIVE*2)/3)*(V_ACTIVE-(V_ACTIVE*2)/3))+31)/32;exit_count=(((H_ACTIVE-(H_ACTIVE*2)/3)*(V_ACTIVE-(V_ACTIVE*2)/3))+63)/64;end
        endcase
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sum_r<=0; n_r<=0; started<=0;
            stats_sum<=0; stats_n<=0; stats_toggle<=0; stats_valid<=0;
            clipped<=0;stats_clipped<=0;stats_local_high<=0;
            col<=0;row<=0;local_enter<=0;local_exit<=0;
            for(k=0;k<9;k=k+1)tile_high[k]<=0;
        end else begin
            stats_valid<=0;
            if (de && user) begin
                if (started && n_r==PIXELS) begin
                    stats_sum<=sum_r; stats_n<=n_r;
                    stats_toggle<=~stats_toggle; stats_valid<=1;
                    stats_clipped<=clipped;
                    stats_local_high<=local_enter?2'd2:local_exit?2'd1:2'd0;
                end
                started<=1; sum_r<={20'd0,yv}; n_r<=1;
                clipped<=clip_pixel?1:0;
                col<=H_ACTIVE==1?0:1;row<=H_ACTIVE==1?1:0;
                local_enter<=near_high && enter_count<=1;local_exit<=near_high && exit_count<=1;
                for(k=0;k<9;k=k+1)tile_high[k]<=0;
                tile_high[0]<=near_high?1:0;
            end else if (de && started && n_r<PIXELS+1) begin
                sum_r<=sum_r+{20'd0,yv}; n_r<=n_r+1'b1;
                if(clip_pixel) clipped<=clipped+1'b1;
                if(col==H_ACTIVE-1)begin col<=0;row<=row+1'b1;end else col<=col+1'b1;
                if(near_high)begin
                    tile_high[tile]<=tile_next;
                    if(tile_next>=enter_count)local_enter<=1;
                    if(tile_next>=exit_count)local_exit<=1;
                end
            end
        end
    end
endmodule
