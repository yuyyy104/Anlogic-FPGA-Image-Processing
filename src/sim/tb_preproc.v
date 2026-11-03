// Independent integer image model. Fixed coordinates, no learned offsets.
`timescale 1ns/1ps
module tb_preproc;
    localparam W=20,H=12,LATENCY=14;
    reg clk=0,rst_n=0,test_done=0;
    always #5 clk=~clk;
    reg [23:0] rgb_in=0,ref_in=0;
    reg [4:0] timing_in=0;
    reg [3:0] mode=0;
    reg [7:0] thresh=96;
    reg split_en=0;
    wire [23:0] rgb_out;
    wire [4:0] timing_out;
    reg [23:0] img[0:H-1][0:W-1];
    integer errors=0,checks=0,pixels=0,frames=0;
    preproc_pipe #(.IMAGE_WIDTH(W)) dut(.clk(clk),.rst_n(rst_n),.rgb_in(rgb_in),
        .timing_in(timing_in),.mode(mode),.thresh(thresh),.split_en(split_en),
        .rgb_out(rgb_out),.timing_out(timing_out),.active_mode(),.active_thresh());
    // 图像像素，越界按 0（零填充）
    function [23:0] pix_at;
        input integer rr;
        input integer cc;
        begin
            if (rr < 0 || cc < 0 || rr >= H || cc >= W) pix_at = 24'd0;
            else pix_at = img[rr][cc];
        end
    endfunction

    function [7:0] y_at;
        input integer rr;
        input integer cc;
        reg [23:0] p;
        integer    v;
        begin
            p = pix_at(rr, cc);
            v = (77*p[23:16] + 150*p[15:8] + 29*p[7:0] + 128) >> 8;
            y_at = v[7:0];
        end
    endfunction

    function [7:0] cb_at;
        input integer rr;
        input integer cc;
        reg [23:0] p;
        integer    v;
        begin
            p = pix_at(rr, cc);
            v = (128*p[7:0] - 43*p[23:16] - 85*p[15:8] + 32768 + 128) >> 8;
            if (v > 255) v = 255;
            if (v < 0)   v = 0;
            cb_at = v[7:0];
        end
    endfunction

    function [7:0] cr_at;
        input integer rr;
        input integer cc;
        reg [23:0] p;
        integer    v;
        begin
            p = pix_at(rr, cc);
            v = (128*p[23:16] - 107*p[15:8] - 21*p[7:0] + 32768 + 128) >> 8;
            if (v > 255) v = 255;
            if (v < 0)   v = 0;
            cr_at = v[7:0];
        end
    endfunction

    function [7:0] quant4;
        input [7:0] v;
        integer q;
        begin
            q = v >> 6;
            quant4 = q * 85;
        end
    endfunction

    function [23:0] styled;
        input [23:0] p;
        integer y,q,lo,hi,rr,gg,bb;
        begin
            y=(77*p[23:16]+150*p[15:8]+29*p[7:0]+128)/256;q=(y/64)*85;
            lo=p[23:16];hi=lo;
            if(p[15:8]<lo)lo=p[15:8];if(p[7:0]<lo)lo=p[7:0];
            if(p[15:8]>hi)hi=p[15:8];if(p[7:0]>hi)hi=p[7:0];
            rr=q+p[23:16]-y;gg=q+p[15:8]-y;bb=q+p[7:0]-y;
            if(rr<0)rr=0;if(rr>255)rr=255;if(gg<0)gg=0;if(gg>255)gg=255;if(bb<0)bb=0;if(bb>255)bb=255;
            styled=hi-lo<=24?{3{q[7:0]}}:{rr[7:0],gg[7:0],bb[7:0]};
        end
    endfunction
    function [7:0] mag_at;              // |Gx| + |Gy| 饱和到 8 位
        input integer rr;
        input integer cc;
        integer gx, gy, m;
        begin
            gx = (y_at(rr-1,cc-1) + 2*y_at(rr-1,cc) + y_at(rr-1,cc+1))
               - (y_at(rr+1,cc-1) + 2*y_at(rr+1,cc) + y_at(rr+1,cc+1));
            gy = (y_at(rr-1,cc-1) + 2*y_at(rr,cc-1) + y_at(rr+1,cc-1))
               - (y_at(rr-1,cc+1) + 2*y_at(rr,cc+1) + y_at(rr+1,cc+1));
            if (gx < 0) gx = -gx;
            if (gy < 0) gy = -gy;
            m = gx + gy;
            if (m > 255) m = 255;
            mag_at = m[7:0];
        end
    endfunction

    function bin_at;                    // 阈值：严格大于
        input integer rr;
        input integer cc;
        begin
            bin_at = (y_at(rr, cc) > thresh) ? 1'b1 : 1'b0;
        end
    endfunction

    function erode_at;                  // 3x3 腐蚀（零填充），即 RTL 的 B 流
        input integer rr;
        input integer cc;
        begin
            erode_at = bin_at(rr-1,cc-1) & bin_at(rr-1,cc) & bin_at(rr-1,cc+1)
                     & bin_at(rr,  cc-1) & bin_at(rr,  cc) & bin_at(rr,  cc+1)
                     & bin_at(rr+1,cc-1) & bin_at(rr+1,cc) & bin_at(rr+1,cc+1);
        end
    endfunction

    function open_at;                   // dilate(erode) = 对 3x3 邻域的 erode 取或
        input integer rr;
        input integer cc;
        integer qr, qc;
        reg     acc;
        begin
            acc = 1'b0;
            for (qr = -1; qr <= 1; qr = qr + 1)
                for (qc = -1; qc <= 1; qc = qc + 1)
                    acc = acc | erode_at(rr+qr, cc+qc);
            open_at = acc;
        end
    endfunction

    // 期望输出：图像像素 (rr,cc) 在 mode 下的 24 位值。越界一律 0（零填充/遮罩）。
    function [23:0] model_pix;
        input [3:0]   m;
        input integer rr;
        input integer cc;
        reg [23:0]    p;
        reg [7:0]     yc;
        begin
            p  = pix_at(rr, cc);
            yc = y_at(rr, cc);
            if (rr < 0 || cc < 0 || rr >= H || cc >= W) model_pix = 24'd0;
            else case (m)
                4'd1: model_pix = {3{yc}};                              // GRAY
                4'd2: model_pix = {3{mag_at(rr,cc)}};                    // SOBEL
                4'd3: model_pix = bin_at(rr,cc) ? 24'hffffff : 24'd0;    // BIN
                4'd4: model_pix = p;                                  // unused mode bypass
                4'd5: model_pix = (mag_at(rr,cc) > 8'd64) ? 24'd0        // CARTOON
                                  : styled(p);
                4'd6: model_pix = {y_at(rr,cc), cb_at(rr,cc), cr_at(rr,cc)}; // YCBCR
                default: model_pix = p;                                  // RAW
            endcase
        end
    endfunction


    reg [23:0] rq[0:LATENCY-1];
    reg [4:0] tq[0:LATENCY-1];
    integer q;
    always @(posedge clk) begin
        if(!rst_n) begin
            for(q=0;q<LATENCY;q=q+1) begin rq[q]<=0;tq[q]<=0;end
        end else begin
            rq[0]<=ref_in;tq[0]<=timing_in;
            for(q=1;q<LATENCY;q=q+1) begin rq[q]<=rq[q-1];tq[q]<=tq[q-1];end
        end
        #1;
        if(!test_done) begin
            checks=checks+1;
            if(rgb_out !== rq[LATENCY-1] || timing_out !== tq[LATENCY-1]) begin
                errors=errors+1;
                if(errors<15) $display("FAIL pixel t=%0t mode=%0d rgb=%h/%h tim=%b/%b",
                    $time,mode,rgb_out,rq[LATENCY-1],timing_out,tq[LATENCY-1]);
            end
            if(timing_out[2]) pixels=pixels+1;
            if(timing_out[2] && timing_out[1]) frames=frames+1;
        end
    end
    task cycle;
        input [23:0] rgb,expected;
        input [4:0] meta;
        begin @(negedge clk);rgb_in=rgb;ref_in=expected;timing_in=meta;end
    endtask
    task pattern;
        input integer pat;
        integer r,c,v,seed;
        reg [23:0] p;
        begin
            seed=17+pat;
            for(r=0;r<H;r=r+1) for(c=0;c<W;c=c+1) begin
                v=0;p=0;
                case(pat)
                    0:p=0;
                    1:p=24'hffffff;
                    2:p=24'hff0000;
                    3:p=24'h00ff00;
                    4:p=24'h0000ff;
                    5:p=(r<H/2) ? ((c<W/2)?24'hff0000:24'h00ff00) : ((c<W/2)?24'h0000ff:24'hffffff);
                    6:begin v=c*12;p={v[7:0],v[7:0],v[7:0]};end
                    7:begin v=r*20;p={v[7:0],v[7:0],v[7:0]};end
                    8:p=(r==4 && c==7)?24'hffffff:0;
                    9:p=(r>=3 && r<=5 && c>=6 && c<=8)?24'hffffff:0;
                    10:p=(r>=2 && r<=6 && c>=5 && c<=9)?24'hffffff:0;
                    11:p=$random(seed);
                    12:begin v=r*W+c;p={r[7:0],c[7:0],v[7:0]};end
                    13:p=(r==0 || c==0 || r==H-1 || c==W-1)?24'hffffff:0;
                    15:p=24'h3f403f;
                    16:p=24'h7f807f;
                    17:p=24'hbfc0bf;
                    18:p=24'h9ab9aa;
                    19:p=24'hb0c8b8;
                    20:p=24'hafc8b8;
                    21:begin v=126+(r+c)%5;p={v[7:0],v[7:0]+8'd1,v[7:0]};end
                    default:p=(r==c/2)?24'hffffff:0;
                endcase
                img[r][c]=p;
            end
        end
    endtask
    task frame;
        input [3:0] m;
        input integer blank;
        input integer split;
        input integer change_mid;
        integer r,c;
        reg [23:0] e;
        begin
            @(negedge clk);mode=m;split_en=split;
            for(r=0;r<H;r=r+1) begin
                if(change_mid && r==H/2) mode=(m+1)%7;
                for(c=0;c<W;c=c+1) begin
                    if(r<2 || c<2) e=0;
                    else if(split && c<W/2) e=pix_at(r-2,c-2);
                    else e=model_pix(m,r-2,c-2);
                    cycle(img[r][c],e,{1'b0,1'b0,1'b1,(r==0 && c==0),(c==W-1)});
                end
                repeat(blank) cycle(24'ha5a5a5,0,5'b01000);
            end
            repeat(25) cycle(24'h123456,0,5'b10000);
        end
    endtask
    integer m,p,t;
    initial begin
        repeat(3) @(negedge clk);
        rst_n=1;
        // Every frame is checked, including the first frame after reset, and all
        // subsequent different images. Zero/short/long blanking exercise prefetch.
        for(m=0;m<7;m=m+1) for(p=0;p<22;p=p+1) begin
            pattern(p);frame(m,p%4,0,1);
        end
        for(m=0;m<7;m=m+1) begin pattern(11);frame(m,37,1,1);end
        for(t=0;t<2;t=t+1) begin
            thresh=(t==0)?0:255;
            for(m=0;m<7;m=m+1) begin pattern(11);frame(m,4,0,0);end
        end
        // Reset while in a partial frame, then check the first complete frame.
        thresh=96;pattern(1);
        for(p=0;p<7;p=p+1) cycle(24'hffffff,0,{3'b001,(p==0),1'b0});
        @(negedge clk);rst_n=0;timing_in=0;ref_in=0;
        repeat(3) @(negedge clk);
        rst_n=1;pattern(11);frame(4,7,0,0);
        repeat(20) cycle(0,0,0);
        // Partial input is reset before it can reach the output.
        if(frames!=176 || pixels!=176*W*H) begin
            errors=errors+1;$display("FAIL frame count=%0d pixels=%0d",frames,pixels);
        end
        test_done=1;
        if(errors==0) $display("PASS preproc checks=%0d pixels=%0d frames=%0d errors=0",checks,pixels,frames);
        else $display("FAIL preproc errors=%0d",errors);
        $finish;
    end
endmodule
