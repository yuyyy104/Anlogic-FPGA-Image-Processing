`timescale 1ns/1ps
// The simulation shell is extracted from design_top_wrapper.v by the Tcl entry.
// Expected geometry and decimal text come from fixed synthetic shapes; no DUT
// coordinates, classifier state or BCD digits participate in the pixel oracle.
module tb_p3_display;
    localparam W=1280, H=720;
    localparam [23:0] BG=24'h303030, RED=24'hff2020;
    reg clk=0, rst_n=0, test_done=0;
    always #5 clk=~clk;
    reg [4:0] req=0;
    reg [23:0] source=0, source1=0, source2=0;
    reg [3:0] mode=0;
    wire read_en, hv, hh, hd;
    wire [23:0] rgb;
    always @(posedge clk) begin source1<=source; source2<=source1; end
    p3_display_glue dut(
        .S_hdmi_pixel_clk(clk), .S_hdmi_rst_n(rst_n), .S_video_rd_data(source2),
        .S_hdmi_vsync(req[4]), .S_hdmi_hsync(req[3]), .S_hdmi_de(req[2]),
        .S_hdmi_user(req[1]), .S_hdmi_last(req[0]),
        .S_preproc_mode(mode), .S_preproc_thresh(8'd96), .S_hdmi_debug_status(4'b1111),
        .S_hdmi_window_rd_en(read_en), .S_hdmi_out_vsync(hv),
        .S_hdmi_out_hsync(hh), .S_hdmi_out_de(hd), .S_hdmi_out_data(rgb));

    integer errors=0, checks=0, result_checks=0, pixels=0;
    integer ae_frames=0;
    integer ae_reference[0:3];
    integer text_pixels=0, rect_pixels=0, circle_pixels=0, cleared_pixels=0;
    integer f,r,c,q;
    integer input_frame=0, input_x=0, input_y=0;
    integer ref_valid, ref_cls, ref_area, rx0,rx1,ry0,ry1;
    integer xc,yc,cell_index,local_x,number,digit;
    reg [7:0] ch=0;
    reg [3:0] fontrow=0;
    wire [15:0] glyph;
    osd_char_lib reference_font(.I_char(ch),.I_row(fontrow),.O_row_bits(glyph));
    reg [23:0] expected=0;
    reg [2:0] coverage=0;
    reg compare_pixel=0;
    reg status_region, text_region, border;
    reg [23:0] rgb_q[0:24];
    reg [4:0] meta_q[0:24];
    reg [2:0] cover_q[0:24];
    reg compare_q[0:24];
    integer frame_q[0:24], x_q[0:24], y_q[0:24];

    `include "D:/codex_project/FPGA_competiton/src/sim/color_matrix_ref.vh"
    function [23:0] pixel;
        input integer frame, y, x;
        integer dx,dy;
        begin
            // Global brightness steps exercise P3 coexistence with P4's
            // suppression. Dedicated P4 tests independently check active boxes.
            pixel=frame%2 ? 24'hd0d0d0 : BG;
            if(frame==0 && x>=200 && x<240 && y>=38 && y<58) pixel=RED;
            dx=x-300; dy=y-100;
            if(frame==1 && dx*dx+dy*dy<=1600) pixel=RED;
        end
    endfunction
    function [23:0] gray;
        input [23:0] value;
        integer yy;
        begin
            yy=(77*value[23:16]+150*value[15:8]+29*value[7:0]+128)/256;
            gray={3{yy[7:0]}};
        end
    endfunction
    task previous_result;
        input integer frame;
        begin
            ref_valid=0;ref_cls=0;ref_area=0;rx0=0;rx1=0;ry0=0;ry1=0;
            if(frame==1) begin
                ref_valid=1;ref_cls=2;ref_area=760;rx0=202;rx1=239;ry0=39;ry1=58;
            end
            if(frame==2) begin
                ref_valid=1;ref_cls=1;ref_area=4865;rx0=262;rx1=340;ry0=62;ry1=140;
            end
        end
    endtask
    task expect_pixel;
        begin
            input_frame=f; input_x=c; input_y=r;
            expected=0; coverage=0;
            compare_pixel=req[2] && c>=192 && !(r>=120 && r<144 && c>=375 && c<575);
            status_region=req[2] && c>=192 && c<464 && r>=16 && r<32;
            text_region=req[2] && ref_valid && c>=192 && c<512 && r>=40 && r<56;
            border=req[2] && ref_valid && c>=rx0+2 && c<=rx1+2 &&
                   r>=ry0+2 && r<=ry1+2 &&
                   (c<=rx0+3 || c>=rx1+1 || r<=ry0+3 || r>=ry1+1);
            if(req[2] && r>=3 && c>=3) begin
                expected=corrected(pixel(f,r-3,c-3));
                if(f%2) expected=gray(expected);
            end
            if(border) begin
                expected=(ref_cls==2)?24'hff2020:24'hffe000;
                coverage=(ref_cls==2)?2:3;
            end
            ch=0; fontrow=0; local_x=0;
            if(text_region) begin
                xc=(rx0+rx1+1)/2+2; yc=(ry0+ry1+1)/2+2;
                cell_index=(c-192)/16; local_x=(c-192)%16; fontrow=r-40;
                number=0; digit=0;
                case(cell_index)
                    0: ch=(ref_cls==2)?"R":"C";
                    1: ch="X";
                    6,12: ch=" ";
                    7: ch="Y";
                    13: ch="A";
                    default: begin
                        if(cell_index<6) begin number=xc; digit=5-cell_index; end
                        else if(cell_index<12) begin number=yc; digit=11-cell_index; end
                        else begin number=ref_area; digit=19-cell_index; end
                        repeat(digit) number=number/10;
                        ch=48+number%10;
                    end
                endcase
            end
            if(status_region) begin
                cell_index=(c-192)/16; local_x=(c-192)%16; fontrow=r-16;
                case(cell_index)
                    0:ch="M";1:ch="O";2:ch="D";3:ch="E";4:ch=":";
                    5:ch=48+f%2;6:ch=" ";7:ch="T";8:ch="H";9:ch=":";
                    10:ch="0";11:ch="9";
                    // PQ 状态栏扩展：单元 13-16 显示 AUTO / MAN。
                    // 本 TB 不产生手动事件 ⇒ ae_ctrl 的 auto_valid 保持 1 ⇒ 期望 "AUTO"。
                    13:ch="A";14:ch="U";15:ch="T";16:ch="O";
                    default:ch="6";
                endcase
            end
            #1;
            if(text_region && glyph[15-local_x]) begin expected=24'h00e6ff;coverage=1;end
            if(status_region && glyph[15-local_x]) begin expected=24'hff0000;coverage=0;end
        end
    endtask
    always @(posedge clk) begin
        if(!rst_n) begin
            for(q=0;q<25;q=q+1) begin
                rgb_q[q]<=0;meta_q[q]<=0;cover_q[q]<=0;compare_q[q]<=0;
                frame_q[q]<=0;x_q[q]<=0;y_q[q]<=0;
            end
        end else begin
            rgb_q[0]<=expected;meta_q[0]<=req;cover_q[0]<=coverage;compare_q[0]<=compare_pixel;
            frame_q[0]<=input_frame;x_q[0]<=input_x;y_q[0]<=input_y;
            for(q=1;q<25;q=q+1) begin
                rgb_q[q]<=rgb_q[q-1];meta_q[q]<=meta_q[q-1];cover_q[q]<=cover_q[q-1];
                compare_q[q]<=compare_q[q-1];frame_q[q]<=frame_q[q-1];
                x_q[q]<=x_q[q-1];y_q[q]<=y_q[q-1];
            end
        end
        #1;
        if(rst_n && !test_done) begin
            if(dut.S_ae_valid) begin
                if(ae_frames>=3 || dut.S_ae_n!==20'd921600 || dut.S_ae_sum!==ae_reference[ae_frames]) begin
                    errors=errors+1;
                    $display("FAIL display AE frame=%0d n=%0d sum=%0d expected=%0d",
                        ae_frames,dut.S_ae_n,dut.S_ae_sum,ae_reference[ae_frames]);
                end
                ae_frames=ae_frames+1;
            end
            checks=checks+1;
            if(read_en!==req[2] || {hv,hh,hd}!==meta_q[24][4:2] ||
               (compare_q[24] && rgb!==rgb_q[24])) begin
                errors=errors+1;
                if(errors<12) $display("FAIL display f=%0d xy=%0d,%0d rgb=%h/%h sync=%b/%b",
                    frame_q[24],x_q[24],y_q[24],rgb,rgb_q[24],{hv,hh,hd},meta_q[24][4:2]);
            end
            if(meta_q[8][2] && meta_q[8][1]) begin
                result_checks=result_checks+1;
                if({dut.S_det_valid,dut.S_det_cls,dut.S_det_area,dut.S_det_xmin,dut.S_det_xmax,
                    dut.S_det_ymin,dut.S_det_ymax} !==
                   {ref_valid[0],ref_cls[1:0],ref_area[19:0],rx0[11:0],rx1[11:0],ry0[11:0],ry1[11:0]}) begin
                    errors=errors+1;
                    $display("FAIL display detection result frame=%0d",frame_q[8]);
                end
            end
            if(hd) pixels=pixels+1;
            if(compare_q[24]) begin
                case(cover_q[24])
                    1:text_pixels=text_pixels+1;
                    2:rect_pixels=rect_pixels+1;
                    3:circle_pixels=circle_pixels+1;
                    default:;
                endcase
                if(frame_q[24]==3 && y_q[24]>=40 && y_q[24]<56 && x_q[24]<512)
                    cleared_pixels=cleared_pixels+1;
            end
            if(errors>=20) begin test_done=1; $finish; end
        end
    end
    initial begin
        repeat(5) @(negedge clk); rst_n=1;
        for(f=0;f<4;f=f+1) begin
            ae_reference[f]=0;
            previous_result(f); mode=f%2;
            for(r=0;r<H;r=r+1) begin
                for(c=0;c<W;c=c+1) begin
                    @(negedge clk);
                    source=pixel(f,r,c);
                    ae_reference[f]=ae_reference[f]+(77*source[23:16]+150*source[15:8]+29*source[7:0]+128)/256;
                    req={2'b00,1'b1,(r==0 && c==0),(c==W-1)};
                    if(f==1 && r==360 && c==0) mode=6; // current frame must remain gray
                    expect_pixel;
                end
                repeat(8) begin @(negedge clk);source=0;req=0;expect_pixel;end
            end
            repeat(32) begin @(negedge clk);source=0;req=0;expect_pixel;end
        end
        repeat(24) @(negedge clk);
        if(ae_frames!=3 || result_checks!=4 || pixels!=4*W*H || text_pixels==0 || rect_pixels==0 ||
           circle_pixels==0 || cleared_pixels!=320*16) begin
            errors=errors+1;
            $display("FAIL display coverage results=%0d pixels=%0d text=%0d rect=%0d circle=%0d clear=%0d",
                result_checks,pixels,text_pixels,rect_pixels,circle_pixels,cleared_pixels);
        end
        test_done=1;
        if(errors==0) $display("PASS p3_display checks=%0d frames=4 results=%0d pixels=%0d text=%0d rect=%0d circle=%0d cleared=%0d errors=0",
            checks,result_checks,pixels,text_pixels,rect_pixels,circle_pixels,cleared_pixels);
        else $display("FAIL p3_display errors=%0d",errors);
        $finish;
    end
endmodule
