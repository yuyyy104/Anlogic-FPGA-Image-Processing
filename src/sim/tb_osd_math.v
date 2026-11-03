`timescale 1ns/1ps
module tb_osd_math;
    reg clk=0,rst_n=0,test_done=0;always #5 clk=~clk;
    reg user=0;reg [7:0] threshold=96;
    reg [11:0] probe_x=0;
    integer errors=0,checks=0,n,d,expected;
    hdmi_mixer #(.STATUS_OSD(1),.READABLE_OSD(1)) dut(
        .I_clk(clk),.I_rst_n(rst_n),.I_video_de(1'b1),.I_video_user(user),.I_video_last(1'b1),
        .I_video_hsync(1'b0),.I_video_vsync(1'b0),.I_video_rd_data(24'd0),
        .I_debug_status(4'hf),.I_mode(4'd0),.I_thresh(threshold),.I_denoise(1'b0),
        .I_ae_src_auto(1'b1),.I_det_valid(1'b0),.I_det_cls(2'd0),.I_det_area(20'd0),
        .I_det_xmin(12'd0),.I_det_xmax(12'd0),.I_det_ymin(12'd0),.I_det_ymax(12'd0),
        .I_mv_valid(1'b0),.I_mv_count(8'd0),.I_mv_overflow(1'b0),.I_mv_global_change(1'b0),
        .I_mv_r0(48'd0),.I_mv_r1(48'd0),.I_mv_r2(48'd0),.I_mv_r3(48'd0),
        .I_lat_ms(16'd0),.I_lat_valid(1'b0),.I_lat_tgl(1'b0));
    initial begin
        repeat(4)@(negedge clk);rst_n=1;
        // Inspect the real character selector. Full raster/pixel rendering is
        // checked separately by readable_osd and mode_osd.
        force dut.S_x_2d=probe_x;force dut.S_y_2d=12'd16;
        for(n=0;n<256;n=n+1)begin
            @(negedge clk);threshold=n;user=1;
            @(negedge clk);user=0;threshold=255-n;
            repeat(9)@(negedge clk);
            for(d=0;d<3;d=d+1)begin
                probe_x=192+(10+d)*16;#2;
                expected=d==0 ? n/100 : d==1 ? (n/10)%10 : n%10;
                checks=checks+1;
                if(dut.status_char!==8'd48+expected)begin errors=errors+1;
                    $display("FAIL threshold %0d digit%0d got%0d",n,d,dut.status_char);end
            end
        end
        for(n=0;n<32;n=n+1)begin
            expected=(n*16/24)%16;checks=checks+1;
            if(dut.scale24(n)!==expected[3:0])begin errors=errors+1;$display("FAIL scale24 %0d",n);end
            expected=(n*16/15)%16;checks=checks+1;
            if(dut.scale15(n)!==expected[3:0])begin errors=errors+1;$display("FAIL scale15 %0d",n);end
        end
        release dut.S_x_2d;release dut.S_y_2d;
        test_done=1;
        if(errors==0)$display("PASS osd_math checks=%0d thresholds=256 scale_inputs=32",checks);
        else $display("FAIL osd_math errors=%0d",errors);
        $finish;
    end
endmodule
