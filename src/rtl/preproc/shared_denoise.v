`timescale 1ns/1ps
// RGB-channel 3x3 median/Gaussian blend, rounded as (median+Gaussian+1)/2.
// Four register stages; display (y,x) represents input (y-1,x-1) in
// both ON and OFF. The top/left pixel is black; full raster timing is retained.
// Read each line at the incoming column and write the preceding registered
// column, avoiding DP read/write collisions even without horizontal blanking.
module shared_denoise #(parameter integer IMAGE_WIDTH=1280)(
    input wire clk, rst_n,
    input wire [23:0] rgb_in,
    input wire [4:0] timing_in,
    input wire enable,
    output reg [23:0] rgb_out,
    output reg [4:0] timing_out,
    output reg active_enable,
    output reg restart
);
    reg [11:0] col,row,x1,y1;
    wire [11:0] x=timing_in[1] ? 12'd0 : col;
    wire [11:0] y=timing_in[1] ? 12'd0 : row;
    reg [23:0] rgb1;
    reg [4:0] t1,t2,t3;
    reg en1,en2,en3,v2,v3;
    wire [23:0] line1,line2;
    wire [23:0] ld[0:1];
    assign line1=ld[0];
    assign line2=ld[1];
    genvar g;
    generate for(g=0;g<2;g=g+1) begin: lines
        PH1P_LOGIC_ERAM #(.DATA_WIDTH_A(24),.DATA_WIDTH_B(24),
            .ADDR_WIDTH_A(11),.ADDR_WIDTH_B(11),.DATA_DEPTH_A(IMAGE_WIDTH),.DATA_DEPTH_B(IMAGE_WIDTH),.BYTE_ENABLE(0),
            .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG")) ram (
            .clka(clk),.cea(1'b1),.ocea(1'b0),.wea(rst_n && t1[2]),
            .addra(x1[10:0]),.dia(g==0 ? rgb1 : line1),.rsta(1'b0),.bea(1'b1),.doa(),
            .clkb(clk),.ceb(timing_in[2]),.oceb(1'b1),.web(1'b0),
            .addrb(x[10:0]),.dib(24'd0),.rstb(1'b0),.beb(1'b1),
            .dob(ld[g]),
            .ecc_sbiterrinj(1'b0),.ecc_dbiterrinj(1'b0),.ecc_sbiterr(),.ecc_dbiterr()
        );
    end endgenerate
    wire [23:0] p[0:2];
    assign p[0]=y1>=2 ? line2 : 24'd0;
    assign p[1]=y1>=1 ? line1 : 24'd0;
    assign p[2]=rgb1;
    reg [23:0] h[0:2][0:1];
    reg [9:0] hs[0:2][0:2];
    reg [23:0] sorted2[0:2][0:2];
    reg [7:0] max_low3[0:2],mid_mid3[0:2],min_high3[0:2];
    reg [11:0] sum[0:2];
    reg [23:0] center2,center3;
    function [23:0] sort3;
        input [7:0] a,b,c;
        reg [7:0] lo,mid,hi,tmp;
        begin
            lo=a;mid=b;hi=c;
            if(lo>mid) begin tmp=lo;lo=mid;mid=tmp;end
            if(mid>hi) begin tmp=mid;mid=hi;hi=tmp;end
            if(lo>mid) begin tmp=lo;lo=mid;mid=tmp;end
            sort3={lo,mid,hi};
        end
    endfunction
    function [7:0] median3;
        input [7:0] a,b,c;
        reg [23:0] ordered;
        begin ordered=sort3(a,b,c);median3=ordered[15:8];end
    endfunction
    function [7:0] min3;
        input [7:0] a,b,c;
        reg [7:0] ab;
        begin ab=a<b?a:b;min3=ab<c?ab:c;end
    endfunction
    function [7:0] max3;
        input [7:0] a,b,c;
        reg [7:0] ab;
        begin ab=a>b?a:b;max3=ab>c?ab:c;end
    endfunction
    wire [8:0] blend[0:2];
    generate for(g=0;g<3;g=g+1) begin: channels
        // For three sorted rows, the middle of these three reductions is
        // exactly the fifth of all nine samples, including duplicate values.
        assign blend[g]={1'b0,sum[g][11:4]} +
            {1'b0,median3(max_low3[g],mid_mid3[g],min_high3[g])}+9'd1;
    end endgenerate
    integer a,b;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            col<=0;row<=0;x1<=0;y1<=0;rgb1<=0;
            t1<=0;t2<=0;t3<=0;timing_out<=0;
            en1<=0;en2<=0;en3<=0;v2<=0;v3<=0;
            active_enable<=0;restart<=0;rgb_out<=0;center2<=0;center3<=0;
            for(a=0;a<3;a=a+1) begin
                h[a][0]<=0;h[a][1]<=0;sum[a]<=0;
                max_low3[a]<=0;mid_mid3[a]<=0;min_high3[a]<=0;
                for(b=0;b<3;b=b+1) begin hs[a][b]<=0;sorted2[a][b]<=0;end
            end
        end else begin
            restart<=timing_in[2] && timing_in[1] && enable!=active_enable;
            if(timing_in[2] && timing_in[1]) active_enable<=enable;
            if(timing_in[2]) begin
                col<=timing_in[0] ? 12'd0 : x+12'd1;
                row<=timing_in[0] ? y+12'd1 : y;
            end
            x1<=x;y1<=y;rgb1<=rgb_in;t1<=timing_in;
            en1<=timing_in[2] && timing_in[1] ? enable : active_enable;
            t2<=t1;en2<=en1;v2<=t1[2] && x1>=1 && y1>=1;
            center2<=h[1][0];
            for(a=0;a<3;a=a+1) begin
                if(t1[2]) begin
                    h[a][0]<=p[a];
                    h[a][1]<=x1==0 ? 24'd0 : h[a][0];
                end
                for(b=0;b<3;b=b+1) begin
                    hs[a][b]<={2'd0,p[a][8*b +: 8]} +
                        (x1>=1 ? {1'd0,h[a][0][8*b +: 8],1'b0} : 10'd0) +
                        (x1>=2 ? {2'd0,h[a][1][8*b +: 8]} : 10'd0);
                    sorted2[a][b]<=sort3(p[a][8*b +: 8],
                        x1>=1 ? h[a][0][8*b +: 8] : 8'd0,
                        x1>=2 ? h[a][1][8*b +: 8] : 8'd0);
                end
            end
            t3<=t2;en3<=en2;v3<=v2;center3<=center2;
            for(b=0;b<3;b=b+1) begin
                sum[b]<={2'd0,hs[0][b]}+{1'd0,hs[1][b],1'b0}+{2'd0,hs[2][b]}+12'd8;
                max_low3[b]<=max3(sorted2[0][b][23:16],sorted2[1][b][23:16],sorted2[2][b][23:16]);
                mid_mid3[b]<=median3(sorted2[0][b][15:8],sorted2[1][b][15:8],sorted2[2][b][15:8]);
                min_high3[b]<=min3(sorted2[0][b][7:0],sorted2[1][b][7:0],sorted2[2][b][7:0]);
            end
            timing_out<=t3;
            for(b=0;b<3;b=b+1)
                rgb_out[8*b +: 8]<=!v3 ? 8'd0 : en3 ? blend[b][8:1] : center3[8*b +: 8];
        end
    end
endmodule
