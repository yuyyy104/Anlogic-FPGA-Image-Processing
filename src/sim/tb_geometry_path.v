`timescale 1ns/1ps
module tb_geometry_path;
localparam W=512,H=256,LAT=32;
reg clk=0,rst=0;always #5 clk=~clk;
reg [23:0] src=0,s1=0,s2=0;reg [4:0] req=0;reg en=0;
wire hv,hh,hd,rd;wire [23:0] out;
p3_display_glue dut(.S_hdmi_pixel_clk(clk),.S_hdmi_rst_n(rst),.S_video_rd_data(s2),
 .S_hdmi_vsync(req[4]),.S_hdmi_hsync(req[3]),.S_hdmi_de(req[2]),.S_hdmi_user(req[1]),.S_hdmi_last(req[0]),
 .S_preproc_mode(4'd0),.S_preproc_thresh(8'd96),.S_hdmi_debug_status(4'b1111),
 .S_cal_stable(en),.S_lock_stable(1'b1),.S_awb_frozen(1'b1),
 .S_hdmi_window_rd_en(rd),.S_hdmi_out_vsync(hv),.S_hdmi_out_hsync(hh),.S_hdmi_out_de(hd),.S_hdmi_out_data(out));
always @(posedge clk)begin s1<=src;s2<=s1;end
reg [23:0] target[0:W*H-1];
integer errors=0,checks=0,boxes=0,x,y,f,k,dx=0,dy=0,df=0;reg test_done=0;
reg [4:0] tq[0:LAT-1];integer xq[0:LAT-1],yq[0:LAT-1],fq[0:LAT-1];
always @(posedge clk)begin
 if(!rst)for(k=0;k<LAT;k=k+1)begin tq[k]<=0;xq[k]<=0;yq[k]<=0;fq[k]<=0;end
 else begin
  tq[0]<=req;xq[0]<=dx;yq[0]<=dy;fq[0]<=df;
  for(k=1;k<LAT;k=k+1)begin tq[k]<=tq[k-1];xq[k]<=xq[k-1];yq[k]<=yq[k-1];fq[k]<=fq[k-1];end
  #1;checks=checks+1;
  if(rd!==req[2] || {hv,hh,hd}!==tq[LAT-1][4:2])begin errors=errors+1;if(errors<5)$display("FAIL geometry_path timing");end
  if(hd && (fq[LAT-1]==1 || fq[LAT-1]==2) && xq[LAT-1]==360 && yq[LAT-1]>=125 && yq[LAT-1]<135)begin
   boxes=boxes+1;if(out!==24'hff2020)begin errors=errors+1;$display("FAIL actual RECT box %h",out);end
  end
 end
end
initial begin
 $readmemh("D:/codex_project/FPGA_competiton/src/sim/fixtures/geometry_path/target.mem",target);
 repeat(5)@(negedge clk);rst=1;
 for(f=0;f<4;f=f+1)begin
  for(y=0;y<H;y=y+1)begin
   for(x=0;x<W;x=x+1)begin
    @(negedge clk);req={2'b00,1'b1,(x==0 && y==0),(x==W-1)};dx=x;dy=y;df=f;src=f<2?target[y*W+x]:24'h606060;
   end
   @(negedge clk);req=0;src=0;repeat(3)@(negedge clk);
  end
  @(negedge clk);req=0;src=0;repeat(49500)@(negedge clk);
  if(f==1 || f==2)begin
   if(dut.S_det_valid!==1 || dut.S_det_cls!==2 || dut.S_det_area!==20'd17651 || dut.S_det_xmin!==12'd156 || dut.S_det_xmax!==12'd358 || dut.S_det_ymin!==12'd42 || dut.S_det_ymax!==12'd216)begin errors=errors+1;$display("FAIL geometry_path packet frame%0d cls%0d area%0d bbox%0d,%0d,%0d,%0d",f,dut.S_det_cls,dut.S_det_area,dut.S_det_xmin,dut.S_det_xmax,dut.S_det_ymin,dut.S_det_ymax);end
  end
  if(f==3 && (dut.S_det_valid!==0 || dut.S_det_cls!==0))begin errors=errors+1;$display("FAIL geometry_path NONE");end
 end
 if(boxes!=20)begin errors=errors+1;$display("FAIL actual box coverage %0d",boxes);end
 test_done=1;if(errors==0)$display("PASS geometry_path rotated_RECT_to_NONE actual_top LSCon GEOMon frame_packet display_box20 timing32 checks%0d",checks);else $display("FAIL geometry_path errors%0d",errors);$finish;
end
endmodule
