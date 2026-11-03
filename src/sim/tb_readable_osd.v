`timescale 1ns/1ps
module tb_readable_osd;
    reg clk=0,rst_n=0,test_done=0;always #5 clk=~clk;
    reg de=0,user=0,last=0;reg [23:0] video=24'hffffff;
    reg dn=0,dvalid=0;reg [1:0] cls=0;reg [3:0] mode=0;
    reg mvvalid=0,mvover=0,mvglobal=0;reg [7:0] count=0;
    wire hd;wire [23:0] rgb;
    hdmi_mixer #(.STATUS_OSD(1),.READABLE_OSD(1)) dut(
        .I_clk(clk),.I_rst_n(rst_n),.I_video_vsync(1'b0),.I_video_hsync(1'b1),
        .I_video_de(de),.I_video_user(user),.I_video_last(last),.I_video_rd_data(video),
        .I_debug_status(4'b1111),.I_mode(mode),.I_thresh(8'd96),.I_denoise(dn),.I_ae_src_auto(1'b1),
        .I_det_valid(dvalid),.I_det_cls(cls),.I_det_area(20'd1234),
        .I_det_xmin(12'd16),.I_det_xmax(12'd24),.I_det_ymin(12'd16),.I_det_ymax(12'd24),
        .I_mv_valid(mvvalid),.I_mv_count(count),.I_mv_overflow(mvover),.I_mv_global_change(mvglobal),
        .I_mv_r0(48'd0),.I_mv_r1(48'd0),.I_mv_r2(48'd0),.I_mv_r3(48'd0),
        .I_lat_ms(16'd0),.I_lat_valid(1'b0),.I_lat_tgl(1'b0),.O_hdmi_de(hd),.O_hdmi_data(rgb)
    );
    integer errors=0,checks=0,panel_pixels=0,font_pixels=0,f,y,x,k,index,localx;
    reg [7:0] ch=0;reg [3:0] row=0;wire [15:0] bits;
    osd_char_lib font(.I_char(ch),.I_row(row),.O_row_bits(bits));
    reg [23:0] expected=0,q[0:2];reg compare=0,cq[0:2];
    reg [8*34-1:0] textline;
    task reference;
        begin
            compare=de&&x>=192&&x<736&&((y>=16&&y<32)||(y>=40&&y<56)||(y>=64&&y<80));
            expected=24'h101820;ch=0;row=0;
            textline=0;index=(x-192)/16;localx=(x-192)%16;
            if(y>=16&&y<32)begin
                row=y-16;textline=dn ? "MODE:0 TH:096AUTO          DN:ON  " : "MODE:0 TH:096AUTO          DN:OFF ";
                textline[8*(33-5) +: 8]=8'd48+f;
            end else if(y>=40&&y<56)begin
                row=y-40;
                if(!dvalid)textline="SHAPE:NONE                        ";
                else if(cls==2)textline="SHAPE:RECT    X0022 Y0022 A001234 ";
                else if(cls==1)textline="SHAPE:CIRCLE  X0022 Y0022 A001234 ";
                else textline="SHAPE:UNKNOWN X0022 Y0022 A001234 ";
            end else begin
                row=y-64;
                if(mvover)textline="MOTION:--- INVALID                ";
                else if(mvglobal)textline="MOTION:--- GLOBAL                 ";
                else if(!mvvalid)textline="MOTION:--- WAIT                   ";
                else if(count==255)textline="MOTION:255 REGIONS                ";
                else if(count==4)textline="MOTION:004 REGIONS                ";
                else textline="MOTION:000 REGIONS                ";
            end
            // Right pad text to exactly 34 ASCII cells. Each literal above is 34 bytes.
            if(index>=0&&index<34)ch=textline[8*(33-index) +: 8];
            #1;
            if(compare&&bits[15-localx])expected=(y>=40&&y<56)?24'h00e6ff:24'hff0000;
        end
    endtask
    always @(posedge clk)begin
        if(!rst_n)for(k=0;k<3;k=k+1)begin q[k]<=0;cq[k]<=0;end
        else begin q[0]<=expected;cq[0]<=compare;
            for(k=1;k<3;k=k+1)begin q[k]<=q[k-1];cq[k]<=cq[k-1];end end
        #1;
        if(rst_n&&!test_done&&cq[2])begin
            checks=checks+1;
            if(q[2]==24'h101820)panel_pixels=panel_pixels+1;else font_pixels=font_pixels+1;
            if(!hd||rgb!==q[2])begin errors=errors+1;
                if(errors<12)$display("FAIL OSD f=%0d y=%0d x=%0d got=%h expected=%h",f,y,x,rgb,q[2]);end
        end
    end
    initial begin
        repeat(5)@(negedge clk);rst_n=1;
        for(f=0;f<7;f=f+1)begin
            mode=f;
            dn=f%2;dvalid=f!=0;cls=f==1?2:f==2?1:3;
            mvvalid=f!=0;count=f==1?4:f==2?255:0;mvover=f==4;mvglobal=f>=3;
            video=f%2 ? 0 : 24'hffffff;
            for(y=0;y<96;y=y+1)begin
                for(x=0;x<800;x=x+1)begin
                    @(negedge clk);de=1;user=y==0&&x==0;last=x==799;reference;
                end
                repeat(4)begin @(negedge clk);de=0;user=0;last=0;reference;end
            end
            repeat(80)begin @(negedge clk);de=0;user=0;reference;end
        end
        repeat(5)@(negedge clk);
        test_done=1;
        if(errors==0&&font_pixels>0&&panel_pixels>0)$display("PASS readable_osd checks=%0d glyph=%0d background=%0d",checks,font_pixels,panel_pixels);
        else begin errors=errors+1;$display("FAIL readable_osd errors=%0d",errors);end
        $finish;
    end
endmodule
