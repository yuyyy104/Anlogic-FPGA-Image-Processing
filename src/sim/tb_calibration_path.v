`timescale 1ns/1ps
// Actual top instances and wiring; reduced raster solely bounds simulator cost.
module tb_calibration_path;
    localparam W=512,H=256;
    reg clk,rst;always #5 clk=~clk;
    reg [23:0] src,s1,s2;
    reg [4:0] req;
    reg en,locked,wb;
    wire hv,hh,hd,read_en;wire [23:0] out;
    p3_display_glue dut(.S_hdmi_pixel_clk(clk),.S_hdmi_rst_n(rst),.S_video_rd_data(s2),
        .S_hdmi_vsync(req[4]),.S_hdmi_hsync(req[3]),.S_hdmi_de(req[2]),.S_hdmi_user(req[1]),.S_hdmi_last(req[0]),
        .S_preproc_mode(4'd0),.S_preproc_thresh(8'd96),.S_hdmi_debug_status(4'b1111),
        .S_cal_stable(en),.S_lock_stable(locked),.S_awb_frozen(wb),
        .S_hdmi_window_rd_en(read_en),.S_hdmi_out_vsync(hv),.S_hdmi_out_hsync(hh),.S_hdmi_out_de(hd),.S_hdmi_out_data(out));
    always @(posedge clk)begin {s1,s2}<={src,s1};end
    integer errors,checks,pixels,box_pixels,text_pixels;
    reg test_done;
    reg [4:0] mq[0:24];
    integer xq[0:24],yq[0:24],fq[0:24];
    integer f,x,y,q,ox,oy,of,cellno,rc;
    integer driven_x,driven_y,driven_f;
    reg [7:0] expected_char;
    reg [3:0] fontrow;
    wire [15:0] glyph;
    reg [23:0] expected_rgb;
    reg compare;
    osd_char_lib oracle_font(.I_char(expected_char),.I_row(fontrow),.O_row_bits(glyph));
    always @(posedge clk)begin
        if(!rst)for(q=0;q<25;q=q+1)begin {mq[q],xq[q],yq[q],fq[q]}=101'd0;end
        else begin
            for(q=24;q>0;q=q-1)begin {mq[q],xq[q],yq[q],fq[q]}={mq[q-1],xq[q-1],yq[q-1],fq[q-1]};end
            {mq[0],xq[0],yq[0],fq[0]}={req,driven_x,driven_y,driven_f};
            #1;checks=checks+1;
            if(read_en!==req[2] || {hv,hh,hd}!==mq[24][4:2])begin errors=errors+1;if(errors<6)$display("FAIL calibration timing");end
            if(hd)begin
                pixels=pixels+1;{ox,oy,of,compare,expected_rgb}={xq[24],yq[24],fq[24],1'b0,24'd0};
                cellno=(ox-192)/16;
                if(oy>=88 && oy<104 && ox>=192 && ox<512 && (cellno==5 || cellno==10 || cellno==16))begin
                    expected_char=(cellno==5?(of>=1):(cellno==10?(of>=3):(of>=1)))?"1":"0";
                    fontrow=oy-88;{compare,text_pixels}={1'b1,text_pixels+32'd1};
                end
                if(of>=5 && oy>=112 && oy<128 && ox>=224 && ox<272)begin
                    expected_char=cellno==2?(of>=9?"2":"0"):(cellno==3?(of>=9?"5":"3"):"2");
                    fontrow=oy-112;{compare,text_pixels}={1'b1,text_pixels+32'd1};
                end
                if(compare)begin #1;expected_rgb=glyph[15-(ox-192)%16]?24'h00ffff:24'h101820;end
                if(of>=1 && ox>=227 && ox<=290 && oy>=99 && oy<=162 && (ox==227 || ox==290 || oy==99 || oy==162))begin
                    {expected_rgb,compare,box_pixels}={24'h00ffff,1'b1,box_pixels+32'd1};
                end
                if(ox==400 && oy==200)begin {expected_rgb,compare}={24'h606060,1'b1};end
                if(compare && out!==expected_rgb)begin errors=errors+1;if(errors<8)$display("FAIL CAL pixels f=%0d xy=%0d,%0d mix=%0d,%0d hit=%b %h/%h",of,ox,oy,dut.u_hdmi_mixer.S_x_2d,dut.u_hdmi_mixer.S_y_2d,dut.u_hdmi_mixer.cal_hit,out,expected_rgb);end
            end
        end
    end
    initial begin
        {clk,rst,src,s1,s2,req,en,locked,wb,test_done,errors,checks,pixels,box_pixels,text_pixels,f,x,y,driven_x,driven_y,driven_f}=435'd0;
        repeat(5)@(negedge clk);rst=1;
        for(f=0;f<10;f=f+1)begin
            for(y=0;y<H;y=y+1)begin
                for(x=0;x<W;x=x+1)begin
                    @(negedge clk);
                    {req,driven_x,driven_y,driven_f,src}={{2'b0,1'b1,(x==0 && y==0),(x==W-1)},x,y,f,
                        (x>=224 && x<288 && y>=96 && y<160)?(f>=5?24'hfc5080:24'h206080):24'h606060};
                    if(f==0 && y==200 && x==0)begin {en,locked}=2'b11;end
                    if(f==2 && y==200 && x==0)wb=1;
                end
                @(negedge clk);{req,src}=29'd0;repeat(8)@(negedge clk);
            end
            {req,src}=29'd0;repeat(40)@(negedge clk);
            checks=checks+1;
            if(f>=5 && (dut.S_cal_valid!==1 || dut.S_cal_rgb!==(f>=9?24'hfc5080:24'h206080) || dut.S_cal_clipped!==(f>=9?13'd4096:13'd0)))begin errors=errors+1;$display("FAIL actual sampler payload f=%0d %h clips=%0d",f,dut.S_cal_rgb,dut.S_cal_clipped);end
        end
        repeat(24)@(negedge clk);
        if(pixels!=10*W*H || box_pixels==0 || text_pixels==0)begin errors=errors+1;$display("FAIL calibration coverage");end
        test_done=1;if(errors==0)$display("PASS calibration_path checks=%0d pixels=%0d box=%0d text=%0d CAL1 actual_wiring errors=0",checks,pixels,box_pixels,text_pixels);else $display("FAIL calibration_path errors=%0d",errors);$finish;
    end
endmodule
