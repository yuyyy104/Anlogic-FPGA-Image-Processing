`timescale 1ns/1ps
// Sparse RAW10 drives the production demosaic and the production frame AWB.
module tb_awb_raw_path;
    reg clk=0,rst=0,valid=0,user=0,last=0,test_done=0;
    always #5 clk=~clk;
    reg [39:0] raw=0;
    wire [127:0] dem;
    wire [95:0] pixels,out_pixels;
    wire dv,du,dl,ov,ou,ol;
    demosaic #(.IMG_WIDTH(1280),.IMG_HEIGHT(720),.BAYER_MODE("BGGR")) demosaic_dut(
        .I_clk(clk),.I_rst_n(rst),.axi4s_video_tdata(raw),.axi4s_video_tdest(10'd0),
        .axi4s_video_tvalid(valid),.axi4s_video_tuser(user),.axi4s_video_tlast(last),
        .axi4s_video_tready(),.O_tdata(dem),.O_tvalid(dv),.O_tuser(du),.O_tlast(dl),.O_tready(1'b1));
    data128_96 unpack(.I_tdata(dem),.O_tdata(pixels));
    frame_awb awb(.I_clk(clk),.I_rst_n(rst),.I_tvalid(dv),.I_tuser(du),.I_tlast(dl),
        .I_tdata(pixels),.I_freeze(1'b0),.I_tready(),.O_tdata(out_pixels),
        .O_tvalid(ov),.O_tuser(ou),.O_tlast(ol),.O_tready(1'b1),.O_frozen());
    integer errors=0,checks=0,frames=0,words=0,lines=0,line_words=0,known=0;
    integer x,y,f,j,lane;
    reg dv_old=0,du_old=0;
    task check;
        input [255:0] label;input ok;
        begin checks=checks+1;if(ok!==1'b1)begin errors=errors+1;$display("FAIL RAW %0s words=%0d lines=%0d awb=%0d/%0d/%b",label,words,lines,awb.words,awb.lines,awb.line_bad);end end
    endtask
    always @(posedge clk) begin
        #1;
        if(rst && !test_done) begin
            if(du && !du_old) begin
                if(frames>0) begin
                    check("complete output raster",words==230400 && lines==720);
                    check("AWB accepts real raster",awb.words==230400 && awb.lines==720 && !awb.line_bad);
                end
                frames=frames+1;words=0;lines=0;line_words=0;
            end
            if(dv) begin
                if(frames>=2 && lines>=8 && lines<710 && line_words>=8 && line_words<312) begin
                    for(lane=0;lane<4;lane=lane+1) begin
                        checks=checks+1;known=known+1;
                        if(pixels[lane*24 +:24]!==24'h506478) begin
                            errors=errors+1;
                            if(errors<8)$display("FAIL RAW Bayer RGB lane=%0d line=%0d col=%0d rgb=%h",lane,lines,line_words,pixels[lane*24 +:24]);
                        end
                    end
                end
                words=words+1;line_words=line_words+1;
            end else if(dv_old) begin
                check("320 word burst",line_words==320);line_words=0;lines=lines+1;
            end
            du_old=du;dv_old=dv;
        end
    end
    initial begin
        repeat(6)@(negedge clk);rst=1;
        for(f=0;f<3;f=f+1) begin
            @(negedge clk);user=1;valid=0;last=0;
            @(negedge clk);user=0;repeat(16)@(negedge clk);
            for(y=0;y<720;y=y+1) begin
                for(x=0;x<320;x=x+1) begin
                    @(negedge clk);valid=1;last=x==319;
                    raw=(y%2==0) ? {10'd400,10'd480,10'd400,10'd480} :
                                         {10'd320,10'd400,10'd320,10'd400};
                    if(x%4==3 && x<319)begin @(negedge clk);valid=0;last=0;end
                end
                @(negedge clk);valid=0;last=0;repeat(400)@(negedge clk);
            end
            repeat(1000)@(negedge clk);
        end
        check("three complete frames",words==230400 && lines==720 && known>1000000);
        for(x=0;x<5;x=x+1)check("eligible actual RAW patch statistics",awb.counts[x]==1024 && awb.sums_r[x]!=0 && awb.sums_b[x]!=0);
        @(negedge clk);user=1;@(negedge clk);user=0;repeat(1000)@(negedge clk);
        // Uniform 80/100/120 RAW demosaic plus independently computed five
        // calibration ratios: four-edge-region mean is R333/B215, +/-4 for
        // the real demosaic integer rounding at the selected locations.
        check("real RAW calibrated ratios ready",awb.pending && awb.pending_r>=329 && awb.pending_r<=337 &&
            awb.pending_b>=211 && awb.pending_b<=219);
        test_done=1;
        if(errors==0)$display("PASS awb_raw_path checks=%0d known=%0d frames=3 geometry=1280x720 errors=0",checks,known);
        else $display("FAIL awb_raw_path errors=%0d ratio=%0d/%0d",errors,awb.pending_r,awb.pending_b);
        $finish;
    end
endmodule
