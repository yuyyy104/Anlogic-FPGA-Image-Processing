`timescale 1ns/1ps
// Test status glyph placement, frame latching and unchanged three-stage timing.
// Glyph shape comes from the existing font ROM; physical readability is L3.
//
// Logo coverage: the status region (x 192..399) and the logo region (x,y < 160) are
// disjoint, so the status checks never exercised the logo ROM path; the readback TB
// only reaches about 8 rows of a frame, and the first opaque logo pixel is at y=34
// (address 5494). This TB therefore adds two checks on the whole raster:
//   (a) the DUT's internal S_logo_addr must equal independent integer y*160+x
//       (dense over the logo region, including y>=32 where a width-truncated shift
//       would break);
//   (b) the displayed pixel must match a reference anlogic_logo_rom instance
//       addressed by that independent integer address.
//
// Detection overlay: the last two frames drive a valid detect result whose box
// crosses the status region, so the documented priority is checked on real pixels:
// status line > detection overlay > logo > video. The text line (y 40..56) is out of
// this TB's 36-row raster and is covered by tb_detect_osd instead.
module tb_mode_osd;
    reg clk=0,rst_n=0,test_done=0;
    always #5 clk=~clk;
    reg [4:0] tim=0;
    reg [3:0] mode=0;
    reg [7:0] threshold=96;
    reg src_auto=1;
    // P3 detection result driven into the mixer
    reg        d_valid=0;
    reg [1:0]  d_cls=0;
    reg [19:0] d_area=0;
    reg [11:0] d_xmin=0,d_xmax=0,d_ymin=0,d_ymax=0;
    wire [23:0] rgb;
    wire vs,hs,de;
    hdmi_mixer #(.H_OFFSET(0),.V_OFFSET(0),.STATUS_OSD(1)) dut(
        .I_clk(clk),.I_rst_n(rst_n),.I_video_vsync(tim[4]),.I_video_hsync(tim[3]),
        .I_video_de(tim[2]),.I_video_user(tim[1]),.I_video_last(tim[0]),
        .I_ae_src_auto(src_auto), .I_debug_status(4'b1111),.I_mode(mode),.I_thresh(threshold),
        .I_mv_valid(1'b0),.I_mv_count(8'd0),.I_mv_overflow(1'b0),.I_mv_global_change(1'b0),
        .I_mv_r0(48'd0),.I_mv_r1(48'd0),.I_mv_r2(48'd0),.I_mv_r3(48'd0),
        .I_det_valid(d_valid),.I_det_cls(d_cls),.I_det_area(d_area),
        .I_det_xmin(d_xmin),.I_det_xmax(d_xmax),.I_det_ymin(d_ymin),.I_det_ymax(d_ymax),
        .I_video_rd_data(24'h123456),.O_video_rd_en(),
        .O_hdmi_vsync(vs),.O_hdmi_hsync(hs),.O_hdmi_de(de),.O_hdmi_data(rgb));
    reg [7:0] ch=0;
    reg [3:0] fontrow=0;
    wire [15:0] bits;
    osd_char_lib reference_font(.I_char(ch),.I_row(fontrow),.O_row_bits(bits));
    reg  [14:0] ref_addr=0;
    wire [24:0] ref_pixel;
    anlogic_logo_rom reference_logo(.I_addr(ref_addr),.O_pixel(ref_pixel));
    reg region=0;
    reg logo_region=0;
    reg det_box=0;
    reg [23:0] expected=24'h123456;
    reg [23:0] eq[0:2];
    reg [2:0] tq[0:2];
    reg regionq[0:2];
    integer errors=0,checks=0,red_pixels=0,q;
    integer addr_checks=0,addr_errors=0,logo_expect=0,det_expect=0,warmup=0,want_addr;
    integer dx0,dx1,dy0,dy1;
    always @(posedge clk) begin
        if(!rst_n) warmup <= 0;
        else if(warmup < 20) warmup <= warmup + 1;
        // (a) internal ROM address == independent integer y*160+x, alignment free
        if(rst_n && !test_done && dut.S_video_de_2d &&
           dut.S_x_2d < 12'd160 && dut.S_y_2d < 12'd160) begin
            want_addr = dut.S_y_2d * 160 + dut.S_x_2d;
            addr_checks = addr_checks + 1;
            if(dut.S_logo_addr !== want_addr[14:0]) begin
                addr_errors = addr_errors + 1;
                if(addr_errors < 5) $display("FAIL logo addr y=%0d x=%0d got=%0d want=%0d",
                    dut.S_y_2d,dut.S_x_2d,dut.S_logo_addr,want_addr);
            end
        end
        if(!rst_n) begin
            for(q=0;q<3;q=q+1) begin eq[q]<=0;tq[q]<=0;regionq[q]<=0;end
        end else begin
            eq[0]<=expected;tq[0]<=tim[4:2];regionq[0]<=region;
            for(q=1;q<3;q=q+1) begin eq[q]<=eq[q-1];tq[q]<=tq[q-1];regionq[q]<=regionq[q-1];end
        end
        #1;
        // warm-up: the mixer's own data pipeline is three stages deep
        if(!test_done && warmup > 9) begin
            checks=checks+1;
            if({vs,hs,de}!==tq[2] || rgb!==eq[2]) begin
                errors=errors+1;
                if(errors<12) $display("FAIL OSD rgb=%h/%h tim=%b/%b x2d=%0d y2d=%0d det=%b st=%b time=%0t",
                    rgb,eq[2],{vs,hs,de},tq[2],dut.S_x_2d,dut.S_y_2d,dut.det_ov_valid,dut.status_on,$time);
            end
            if(regionq[2] && rgb==24'hff0000) red_pixels=red_pixels+1;
        end
    end
    integer f,r,c,idx,localx,v;
    reg [7:0] frame_thr;
    initial begin
        repeat(4) @(negedge clk);rst_n=1;
        for(f=0;f<11;f=f+1) begin
            src_auto=(f%2==0); repeat(5) @(negedge clk);
            mode=f%7;frame_thr=32+f*25;threshold=frame_thr;
            if(f>=9) begin
                // valid detection result; display box x 200..300, y 10..25 crosses the
                // status cell rows (16..31), so the priority is exercised
                d_valid=1; d_cls=2; d_area=252;
                d_xmin=198; d_xmax=298; d_ymin=8; d_ymax=23;
            end else begin
                d_valid=0; d_cls=0; d_area=0;
                d_xmin=0; d_xmax=0; d_ymin=0; d_ymax=0;
            end
            for(r=0;r<36;r=r+1) begin
                for(c=0;c<480;c=c+1) begin
                    @(negedge clk);
                    if(r==8) begin mode=(f+1)%7;threshold=255;src_auto=(f%2!=0);end
                    tim={2'b00,1'b1,(r==0 && c==0),(c==479)};
                    region=(r>=16 && r<32 && c>=192 && c<464);
                    localx=c-192;idx=localx/16;fontrow=r-16;
                    case(idx)
                        0:ch="M";1:ch="O";2:ch="D";3:ch="E";4:ch=":";5:ch=48+(f%7);
                        7:ch="T";8:ch="H";9:ch=":";
                        10:ch=48+frame_thr/100;11:ch=48+(frame_thr/10)%10;
                        12:ch=48+frame_thr%10;
                        13:ch=(f%2==0)?"A":"M";14:ch=(f%2==0)?"U":"A";
                        15:ch=(f%2==0)?"T":"N";16:ch=(f%2==0)?"O":0;
                        default:ch=0;
                    endcase
                    logo_region=(r<160 && c<160);
                    ref_addr=logo_region ? (r*160+c) : 15'd0;
                    // detection overlay model: two-pixel border of the display window
                    dx0=d_xmin+2; dx1=d_xmax+2; dy0=d_ymin+2; dy1=d_ymax+2;
                    det_box = d_valid &&
                              (c>=dx0) && (c<=dx1) && (r>=dy0) && (r<=dy1) &&
                              ((c<=dx0+1)||(c>=dx1-1)||(r<=dy0+1)||(r>=dy1-1));
                    #1;
                    if(region && bits[15-(localx%16)]) expected=24'hff0000;
                    else if(det_box) begin
                        expected=(d_cls==2)?24'hff2020:(d_cls==1)?24'hffe000:24'hff00ff;
                        det_expect=det_expect+1;
                    end
                    else if(logo_region && ref_pixel[24]) begin
                        expected=ref_pixel[23:0];
                        logo_expect=logo_expect+1;
                    end
                    else expected=24'h123456;
                end
                repeat(5) begin @(negedge clk);tim=0;region=0;logo_region=0;det_box=0;expected=24'h123456;end
            end
            repeat(10) begin @(negedge clk);tim=0;region=0;logo_region=0;det_box=0;expected=24'h123456;end
        end
        if(red_pixels==0) errors=errors+1;
        // the logo path and the detection overlay coverage must not be vacuous
        if(addr_checks<1000) begin errors=errors+1;
            $display("FAIL logo addr checks=%0d (too few)",addr_checks); end
        if(addr_errors!=0) errors=errors+1;
        if(logo_expect==0) begin errors=errors+1;
            $display("FAIL logo opaque pixels never expected"); end
        if(det_expect==0) begin errors=errors+1;
            $display("FAIL detection overlay never expected"); end
        test_done=1;
        if(errors==0) $display("PASS mode_osd checks=%0d red_pixels=%0d logo_addr_checks=%0d logo_pixels=%0d det_pixels=%0d errors=0",
            checks,red_pixels,addr_checks,logo_expect,det_expect);
        else $display("FAIL mode_osd errors=%0d",errors);
        $finish;
    end
endmodule
