`timescale 1ns/1ps
// Real video_out unpacker + display adapter + normal mixer path.
// Only the vendor FIFO is replaced; this test does not validate DDR or CDC.
module tb_video_readback;
    reg clk=0, rst_n=0, wr_valid=0;
    reg [127:0] wr_data=0;
    reg [4:0] timing=0;
    wire read_en;
    wire [23:0] read_rgb, processed_rgb, hdmi_rgb;
    wire [4:0] processed_timing;
    wire hv, hh, hd;
    reg [23:0] expected_rgb[0:7];
    reg [4:0] expected_timing[0:7];
    reg [23:0] stimulus_rgb=0;
    reg [383:0] packed_pixels;
    integer errors=0, checks=0, pixels=0, x=0;
    integer frame, row, group_index, p, col, i;
    reg test_done=0;

    // Independent expected stream: unpacker 2 stages, algorithm 14, mixer 3.
    reg [23:0] in_rgb_q[0:1], proc_q[0:24];
    reg [4:0] meta_q[0:24];
    integer ix=0,iy=0,ff=-1,qq;
    reg [23:0] expected_current;
    always #5 clk=~clk;

    video_out u_read (
        .I_rst_n(rst_n), .I_ddr_clk(clk), .I_video_in_wr_busy(1'b1),
        .I_video_out_rp(2'd0), .I_ddr_user_ready(1'b0),
        .O_video_out_rd_busy(), .O_ddr_user_rd_en(), .O_ddr_user_addr(),
        .I_ddr_user_rd_valid(wr_valid), .I_ddr_user_rd_data(wr_data),
        .I_dsi_clk(clk), .I_video_vsync(timing[4]),
        .I_video_rd_en(read_en), .O_vdieo_data(read_rgb)
    );
    video_display_pipe #(.IMAGE_WIDTH(1280), .MODE(0)) u_pipe (
        .clk(clk), .rst_n(rst_n), .read_rgb(read_rgb), .request_timing(timing),
        .i_denoise(1'b0), .i_mode(4'd0), .i_thresh(8'd96), .i_use_btn(1'b0),
        .read_en(read_en), .rgb_out(processed_rgb), .timing_out(processed_timing),
        .active_mode(), .active_thresh(),
        .det_valid(), .det_cls(), .det_area(),
        .det_xmin(), .det_xmax(), .det_ymin(), .det_ymax());
    hdmi_mixer #(.H_OFFSET(0),.V_OFFSET(0),.IMG_WIDTH(1280),.IMG_HEIGHT(720),.DEBUG_MODE(0)) u_mixer (
        .I_clk(clk), .I_rst_n(rst_n), .I_video_vsync(processed_timing[4]),
        .I_video_hsync(processed_timing[3]), .I_video_de(processed_timing[2]),
        .I_video_user(processed_timing[1]), .I_video_last(processed_timing[0]),
        .I_debug_status(4'b1111), .I_mode(4'd0), .I_thresh(8'd96), .I_video_rd_data(processed_rgb), .O_video_rd_en(),
        .I_det_valid(1'b0), .I_det_cls(2'd0), .I_det_area(20'd0),
        .I_det_xmin(12'd0), .I_det_xmax(12'd0), .I_det_ymin(12'd0), .I_det_ymax(12'd0),
        .I_mv_valid(1'b0), .I_mv_count(8'd0),
        .I_mv_overflow(1'b0), .I_mv_global_change(1'b0),
        .I_mv_r0(48'd0), .I_mv_r1(48'd0), .I_mv_r2(48'd0), .I_mv_r3(48'd0),
        .O_hdmi_vsync(hv), .O_hdmi_hsync(hh), .O_hdmi_de(hd), .O_hdmi_data(hdmi_rgb)
    );
    `include "D:/codex_project/FPGA_competiton/src/sim/color_matrix_ref.vh"
    function [23:0] pixel;
        input integer f, y, c;
        reg [7:0] r,g,b;
        begin
            r=c+17*y+31*f; g=c*7+y*13+f; b=c*19+y+f*53;
            pixel={r,g,b};
        end
    endfunction
    function [23:0] gray;
        input [23:0] rgb;
        integer value;
        begin
            value=(77*rgb[23:16]+150*rgb[15:8]+29*rgb[7:0]+128)/256;
            gray={3{value[7:0]}};
        end
    endfunction
    always @(posedge clk) begin
        if(!rst_n) begin
            ix=0;iy=0;ff=-1;
            for(qq=0;qq<2;qq=qq+1) in_rgb_q[qq]<=0;
            for(qq=0;qq<25;qq=qq+1) begin proc_q[qq]<=0;meta_q[qq]<=0;end
        end else begin
            if(timing[2] && timing[1]) begin ix=0;iy=0;ff=ff+1;end
            expected_current=0;
            if(timing[2] && iy>=3 && ix>=3) expected_current=corrected(pixel(ff,iy-3,ix-3));
            in_rgb_q[0]<=stimulus_rgb;in_rgb_q[1]<=in_rgb_q[0];
            proc_q[0]<=expected_current;meta_q[0]<=timing;
            for(qq=1;qq<25;qq=qq+1) begin proc_q[qq]<=proc_q[qq-1];meta_q[qq]<=meta_q[qq-1];end
            if(timing[2]) begin
                if(timing[0]) begin ix=0;iy=iy+1;end else ix=ix+1;
            end
        end
        #1;
        if(!test_done) begin
            checks=checks+1;
            if(processed_timing !== meta_q[21] || read_en !== timing[2] ||
               processed_rgb !== proc_q[21] || {hv,hh,hd} !== meta_q[24][4:2] ||
               (hd && hdmi_rgb !== proc_q[24]) ||
               (meta_q[1][2] && read_rgb !== in_rgb_q[1])) begin
                errors=errors+1;
                if(errors<12) $display("FAIL readback t=%0t unpack=%h/%h pipe=%h/%h hdmi=%h/%h timing=%b/%b",
                    $time,read_rgb,in_rgb_q[1],processed_rgb,proc_q[21],hdmi_rgb,proc_q[24],processed_timing,meta_q[21]);
            end
            if(hd) pixels=pixels+1;
        end
    end
    task drive;
        input [23:0] rgb;
        input [4:0] meta;
        begin @(negedge clk); stimulus_rgb=rgb; timing=meta; end
    endtask
    initial begin
        repeat(5) @(negedge clk);
        rst_n=1;
        for(frame=0;frame<2;frame=frame+1) begin
            drive(0,5'b10000);
            repeat(30) drive(0,0); // allow the real frame-triggered FIFO reset
            for(row=0;row<4;row=row+1) begin
                // 16 RGB888 pixels form exactly three 128-bit words.
                // Feed one line (240 words), within the 512-word FIFO capacity.
                for(group_index=0;group_index<80;group_index=group_index+1) begin
                    for(p=0;p<16;p=p+1)
                        packed_pixels[383-p*24 -: 24]=pixel(frame,row,group_index*16+p);
                    for(p=0;p<3;p=p+1) begin
                        @(negedge clk); wr_valid=1; wr_data=packed_pixels[383-p*128 -: 128];
                    end
                end
                @(negedge clk); wr_valid=0;
                drive(0,5'b01000);
                for(col=0;col<1280;col=col+1)
                    drive(pixel(frame,row,col),{2'b00,1'b1,(row==0 && col==0),(col==1279)});
                repeat(24) drive(0,0);
            end
        end
        repeat(24) drive(0,0);
        @(negedge clk);
        errors=errors+u_read.U_w128_d512_fifo.errors;
        if(pixels!=10240) errors=errors+1;
        test_done=1;
        if(errors==0) $display("PASS video_readback checks=%0d pixels=%0d (real unpacker/mixer, modeled FIFO)",checks,pixels);
        else $display("FAIL video_readback errors=%0d pixels=%0d",errors,pixels);
    end
endmodule

// Test-only queue with the configured non-show-ahead synchronous read contract.
// Shared clock in this test: no vendor memory, pointer synchronizers or CDC proof.
module w128_d512_fifo (
    input rst,clkw,clkr,we,re, input [127:0] di,
    output reg [127:0] dout=0, output reg valid=0,
    output full_flag,empty_flag,afull,aempty,
    output [8:0] wrusedw,rdusedw
);
    reg [127:0] mem[0:511];
    integer wp=0,rp=0,errors=0;
    wire [31:0] count=wp-rp;
    assign wrusedw=count[8:0]; assign rdusedw=count[8:0];
    assign full_flag=count>=512; assign empty_flag=count==0;
    assign afull=count>=253; assign aempty=count<=2;
    always @(posedge clkw or posedge rst) begin
        if(rst) wp<=0;
        else if(we) begin
            if(full_flag) begin errors=errors+1; $display("FAIL FIFO overflow"); end
            mem[wp%512]<=di; wp<=wp+1;
        end
    end
    always @(posedge clkr or posedge rst) begin
        if(rst) begin rp<=0; dout<=0; valid<=0; end
        else begin
            valid<=re;
            if(re) begin
                if(empty_flag) begin errors=errors+1; $display("FAIL FIFO underflow"); end
                dout<=mem[rp%512]; rp<=rp+1;
            end
        end
    end
endmodule
