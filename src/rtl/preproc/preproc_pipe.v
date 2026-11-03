// One pixel per DE, no backpressure. All modes share one causal 5x5 window.
// Output display (r,c) represents source (r-2,c-2); top/left two pixels are black.
// Neighbours outside the source frame are zero. Last two source rows/columns are
// cropped by this common spatial delay; HS/VS/DE/user/last retain the full raster.
// The register latency is 14 clocks for every mode, separately from this spatial
// translation. Blanking freezes line/tap memories, but timing advances every clock.
`timescale 1ns/1ps
module preproc_pipe #(parameter integer IMAGE_WIDTH=1280)(
    input wire clk, input wire rst_n,
    input wire [23:0] rgb_in, input wire [4:0] timing_in,
    input wire [3:0] mode, input wire [7:0] thresh, input wire split_en,
    output wire [23:0] rgb_out, output wire [4:0] timing_out,
    output wire [3:0] active_mode, output wire [7:0] active_thresh
);
    reg [3:0] mode_a;
    reg [7:0] thr_a;
    reg sp_a;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin mode_a<=0; thr_a<=96; sp_a<=0; end
        else if (timing_in[2] && timing_in[1]) begin
            mode_a<=mode; thr_a<=thresh; sp_a<=split_en;
        end

    assign active_mode=mode_a;
    assign active_thresh=thr_a;
    // Two further registers align the frame-latched controls with tim3, including
    // the previous frame tail when vertical blanking is shorter than three clocks.
    reg [3:0] m1,m2; reg [7:0] th1,th2; reg sp1,sp2;
    always @(posedge clk or negedge rst_n)
        if(!rst_n) begin m1<=0;m2<=0;th1<=96;th2<=96;sp1<=0;sp2<=0;end
        else begin m1<=mode_a;m2<=m1;th1<=thr_a;th2<=th1;sp1<=sp_a;sp2<=sp1;end
    wire [7:0] y3,cb3,cr3;
    wire [23:0] rgb3;
    wire [4:0] tim3;
    rgb2ycbcr u_csc(.clk(clk),.rst_n(rst_n),.rgb_in(rgb_in),.timing_in(timing_in),
        .y_out(y3),.cb_out(cb3),.cr_out(cr3),.rgb_out(rgb3),.timing_out(tim3));
    reg [11:0] col,row;
    wire [11:0] x=tim3[1] ? 12'd0 : col;
    wire [11:0] y=tim3[1] ? 12'd0 : row;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin col<=0; row<=0; end
        else if (tim3[2]) begin
            col<=tim3[0] ? 12'd0 : x+12'd1;
            row<=tim3[0] ? y+12'd1 : y;
        end

    wire [7:0] lines [0:4];
    assign lines[0]=y3;
    genvar g;
    generate for(g=0;g<4;g=g+1) begin: yl
        line_delay #(.WIDTH(IMAGE_WIDTH),.DW(8)) ld(.clk(clk),.we(tim3[2]),
            .col(x),.din(lines[g]),.line_end(tim3[0]),.dout(lines[g+1]));
    end endgenerate
    wire [23:0] raw1,raw2;
    line_delay_eram #(.WIDTH(IMAGE_WIDTH),.DW(24),.AW(11)) rl1(.clk(clk),.we(tim3[2]),
        .col(x),.din(rgb3),.line_end(tim3[0]),.dout(raw1));
    line_delay_eram #(.WIDTH(IMAGE_WIDTH),.DW(24),.AW(11)) rl2(.clk(clk),.we(tim3[2]),
        .col(x),.din(raw1),.line_end(tim3[0]),.dout(raw2));

    // h[r][0] is previous active column; h[r][3] is four columns back.
    reg [7:0] h[0:4][0:3];
    integer a,b;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            for(a=0;a<5;a=a+1) for(b=0;b<4;b=b+1) h[a][b]<=0;
        end else if(tim3[2]) begin
            for(a=0;a<5;a=a+1) begin
                h[a][0]<=lines[a];
                for(b=1;b<4;b=b+1) h[a][b]<=h[a][b-1];
            end
        end
    end

    // S4: top-left to bottom-right window centred on source (y-2,x-2).
    reg [7:0] w[0:4][0:4];
    reg [23:0] raw4;
    reg [4:0] t4;
    reg valid4,split4;
    reg [3:0] mode4;
    reg [7:0] thr4;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            for(a=0;a<5;a=a+1) for(b=0;b<5;b=b+1) w[a][b]<=0;
            raw4<=0; t4<=0; valid4<=0; split4<=0; mode4<=0; thr4<=96;
        end else begin
            for(a=0;a<5;a=a+1) for(b=0;b<5;b=b+1)
                if(tim3[2] && y>=4-a && x>=4-b)
                    if(b==4) w[a][b]<=lines[4-a];
                    else w[a][b]<=h[4-a][3-b];
                else w[a][b]<=0;
            raw4<=raw2; t4<=tim3;
            valid4<=tim3[2] && y>=2 && x>=2;
            split4<=sp2 && x<IMAGE_WIDTH/2;
            mode4<=m2; thr4<=th2;
        end
    end

    wire [11:0] gx_p={4'd0,w[1][1]}+{3'd0,w[1][2],1'b0}+{4'd0,w[1][3]};
    wire [11:0] gx_n={4'd0,w[3][1]}+{3'd0,w[3][2],1'b0}+{4'd0,w[3][3]};
    wire [11:0] gy_p={4'd0,w[1][1]}+{3'd0,w[2][1],1'b0}+{4'd0,w[3][1]};
    wire [11:0] gy_n={4'd0,w[1][3]}+{3'd0,w[2][3],1'b0}+{4'd0,w[3][3]};
    wire [11:0] ax=gx_p>=gx_n ? gx_p-gx_n : gx_n-gx_p;
    wire [11:0] ay=gy_p>=gy_n ? gy_p-gy_n : gy_n-gy_p;
    reg [12:0] magnitude5;
    function [7:0] chroma;
        input [23:0] p; input cr;
        reg [16:0] sum;
        begin
            if(cr) sum=17'd32896+128*p[23:16]-107*p[15:8]-21*p[7:0];
            else sum=17'd32896+128*p[7:0]-43*p[23:16]-85*p[15:8];
            chroma=(sum[16:8]>255) ? 8'd255 : sum[15:8];
        end
    endfunction
    function [7:0] quant4;
        input [7:0] v;
        begin quant4={v[7:6],v[7:6],v[7:6],v[7:6]}; end
    endfunction
    function [7:0] style_clip;
        input signed [9:0] value;
        begin style_clip=value<0?8'd0:value>255?8'd255:value[7:0];end
    endfunction
    function [23:0] style_color;
        input [23:0] p;input [7:0] luminance;
        reg [7:0] lo,hi,q;
        reg signed [9:0] delta;
        begin
            lo=p[23:16]<p[15:8]?p[23:16]:p[15:8];if(p[7:0]<lo)lo=p[7:0];
            hi=p[23:16]>p[15:8]?p[23:16]:p[15:8];if(p[7:0]>hi)hi=p[7:0];
            q=quant4(luminance);
            // One luminance decision for all channels prevents false colour
            // at 64/128/192 boundaries. Weak chroma is treated as neutral.
            delta=$signed({2'd0,q})-$signed({2'd0,luminance});
            if(hi-lo<=24)style_color={3{q}};
            else style_color={style_clip($signed({2'd0,p[23:16]})+delta),
                              style_clip($signed({2'd0,p[15:8]})+delta),
                              style_clip($signed({2'd0,p[7:0]})+delta)};
        end
    endfunction
    reg [23:0] raw5,color5,cartoon5;
    reg [7:0] gray5;
    reg bin5,valid5,split5;
    reg [3:0] mode5;
    reg [4:0] t5;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            magnitude5<=0;raw5<=0;color5<=0;cartoon5<=0;gray5<=0;
            bin5<=0;valid5<=0;split5<=0;mode5<=0;t5<=0;
        end else begin
            magnitude5<={1'b0,ax}+{1'b0,ay};
            raw5<=raw4;gray5<=w[2][2];
            color5<={w[2][2],chroma(raw4,0),chroma(raw4,1)};
            cartoon5<=style_color(raw4,w[2][2]);
            bin5<=w[2][2]>thr4;
            valid5<=valid4;split5<=split4;mode5<=mode4;t5<=t4;
        end
    end
    wire [7:0] mag=magnitude5>255 ? 8'd255 : magnitude5[7:0];
    reg [23:0] result6;
    reg [4:0] t6;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin result6<=0;t6<=0; end
        else begin
            t6<=t5;
            if(!valid5) result6<=0;
            else if(split5) result6<=raw5;
            else case(mode5)
                1: result6<={3{gray5}};
                2: result6<={3{mag}};
                3: result6<=bin5 ? 24'hffffff : 24'd0;
                5: result6<=magnitude5>64 ? 24'd0 : cartoon5;
                6: result6<=color5;
                default: result6<=raw5;
            endcase
        end
    end
    // Eight final registers retain the existing 14-clock public timing contract.
    reg [23:0] rq[0:7]; reg [4:0] tq[0:7];
    integer k;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin for(k=0;k<8;k=k+1) begin rq[k]<=0;tq[k]<=0; end end
        else begin
            rq[0]<=result6;tq[0]<=t6;
            for(k=1;k<8;k=k+1) begin rq[k]<=rq[k-1];tq[k]<=tq[k-1]; end
        end
    end
    assign timing_out=tq[7];
    assign rgb_out=tq[7][2] ? rq[7] : 24'd0;
endmodule
