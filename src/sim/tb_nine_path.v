`timescale 1ns/1ps
module tb_nine_path;
localparam W=1024,H=512,LAT=32;
reg clk=0,rst=0;always #5 clk=~clk;
reg [23:0] src=0,s1=0,s2=0;reg [4:0] req=0;reg en=0,sc=0,sv=0;always #7 sc=~sc;reg [40:0] sd={10'd512,10'd128,11'd1024,3'd0,3'd1,4'd1};
wire hv,hh,hd,rd;wire [23:0] out;
p3_display_glue dut(.S_hdmi_pixel_clk(clk),.S_hdmi_rst_n(rst),.S_video_rd_data(s2),
 .S_hdmi_vsync(req[4]),.S_hdmi_hsync(req[3]),.S_hdmi_de(req[2]),.S_hdmi_user(req[1]),.S_hdmi_last(req[0]),
 .S_preproc_mode(4'd0),.S_preproc_thresh(8'd96),.S_hdmi_debug_status(4'b1111),
 .S_csi_rx_clk(sc),.S_awb_status_src(sd),.S_awb_status_valid(sv),.S_cal_stable(en),.S_lock_stable(1'b1),.S_awb_frozen(1'b1),
 .S_hdmi_window_rd_en(rd),.S_hdmi_out_vsync(hv),.S_hdmi_out_hsync(hh),.S_hdmi_out_de(hd),.S_hdmi_out_data(out));
always @(posedge clk)begin {s1,s2}<={src,s1};end
`include "D:/codex_project/FPGA_competiton/src/sim/color_matrix_ref.vh"
`include "D:/codex_project/FPGA_competiton/src/sim/spatial_nodes_ref.vh"
function [23:0] spatial_ref;
input [23:0] p;input integer xx,yy;
integer base,fx,fy,r,v,b,j,g[0:2];
begin
 base=(yy/128)*11+xx/128;fx=xx%128;fy=yy%128;
 for(j=0;j<3;j=j+1)g[j]=(gain_node(base,j)*(128-fx)*(128-fy)+gain_node(base+1,j)*fx*(128-fy)+gain_node(base+11,j)*(128-fx)*fy+gain_node(base+12,j)*fx*fy+8192)/16384;
 {r,v,b}={(p[23:16]*g[0]+128)/256,(p[15:8]*g[1]+128)/256,(p[7:0]*g[2]+128)/256};
 {r,v,b}={r>255?32'd255:r,v>255?32'd255:v,b>255?32'd255:b};spatial_ref={r[7:0],v[7:0],b[7:0]};
end endfunction
function integer patch;
input integer xx,yy;integer z,cx,cy;
begin patch=-1;for(z=0;z<9;z=z+1)begin
cx=z==1 || z==3 || z==6?W/8:z==2 || z==4 || z==7?W*7/8:W/2;
cy=z==1 || z==2 || z==5?H/8:z==3 || z==4 || z==8?H*7/8:H/2;
if(xx>=cx-32 && xx<cx+32 && yy>=cy-32 && yy<cy+32)patch=z;end end endfunction
function [23:0] pixel;
input integer xx,yy;integer z,rr,gg,bb;
begin z=patch(xx,yy);rr=z<0?96:72+z*8;gg=z<0?96:96+z*7;bb=z<0?96:112+z*5;pixel={rr[7:0],gg[7:0],bb[7:0]};end endfunction
integer sx[0:8],sy[0:8],sum_in[0:26],sum_out[0:26],ci[0:8],co[0:8],ex[0:71];
reg [23:0] pin,pout;integer i,j,x,y,f,k,c,g,expected_bcd,n,value,checks=0,errors=0,pixels=0;
reg test_done=0;reg [4:0] tq[0:LAT-1];integer xq[0:LAT-1],yq[0:LAT-1];
integer dx=0,dy=0,ox,oy,osd_pixels=0;reg [23:0] overlay_q;reg overlay_check;reg [23:0] expected_pixel;
always @(posedge clk)begin
 if(!rst)for(k=0;k<LAT;k=k+1)begin {tq[k],xq[k],yq[k]}<=69'd0;end
 else begin
  {tq[0],xq[0],yq[0]}<={req,dx,dy};
  for(k=1;k<LAT;k=k+1)begin {tq[k],xq[k],yq[k]}<={tq[k-1],xq[k-1],yq[k-1]};end
  overlay_check=dut.u_hdmi_mixer.g_regions.u_cal_osd.en_s && dut.u_hdmi_mixer.S_video_de_2d && dut.u_hdmi_mixer.S_y_2d==304 && dut.u_hdmi_mixer.S_x_2d>=192 && dut.u_hdmi_mixer.S_x_2d<944;
  overlay_q=dut.u_hdmi_mixer.cal_color;
  #1;checks=checks+1;
  if(overlay_check && hd)begin osd_pixels=osd_pixels+1;if(out!==overlay_q)begin errors=errors+1;if(errors<5)$display("FAIL BC row actual HDMI priority %h/%h",out,overlay_q);end end
  if(rd!==req[2] || {hv,hh,hd}!==tq[LAT-1][4:2])begin errors=errors+1;if(errors<5)$display("FAIL spatial_path timing32");end
  if(hd)begin
   pixels=pixels+1;{ox,oy}={xq[LAT-1],yq[LAT-1]};
   // Display source offset is still +3,+3. This patch avoids every overlay.
   if(ox>=110 && ox<150 && oy>=200 && oy<220)begin
    expected_pixel=spatial_ref(corrected(pixel(ox-3,oy-3)),ox-3,oy-3);
    if(out!==expected_pixel)begin errors=errors+1;if(errors<5)$display("FAIL spatial_path RGB xy=%0d,%0d got%h expected%h",ox,oy,out,expected_pixel);end
   end
  end
 end
end
initial begin
 for(g=0;g<9;g=g+1)begin
 sx[g]=(g==1 || g==3 || g==6?W/8:g==2 || g==4 || g==7?W*7/8:W/2)-32;
 sy[g]=(g==1 || g==2 || g==5?H/8:g==3 || g==4 || g==8?H*7/8:H/2)-32;end
 for(g=0;g<9;g=g+1)begin
  {ci[g],co[g]}=64'd0;for(c=0;c<3;c=c+1)begin {sum_in[g*3+c],sum_out[g*3+c]}=64'd0;end
  for(y=sy[g];y<sy[g]+64;y=y+1)for(x=sx[g];x<sx[g]+64;x=x+1)begin
   pin=corrected(pixel(x,y));pout=spatial_ref(pin,x,y);
   for(c=0;c<3;c=c+1)begin sum_in[g*3+c]=sum_in[g*3+c]+((pin>>(16-c*8))&255);sum_out[g*3+c]=sum_out[g*3+c]+((pout>>(16-c*8))&255);end
   if(pin[23:16]>=250 || pin[15:8]>=250 || pin[7:0]>=250)ci[g]=ci[g]+1;
   if(pout[23:16]>=250 || pout[15:8]>=250 || pout[7:0]>=250)co[g]=co[g]+1;
  end
  for(c=0;c<3;c=c+1)begin ex[g*8+c]=sum_in[g*3+c]/4096;ex[g*8+c+3]=sum_out[g*3+c]/4096;end
  {ex[g*8+6],ex[g*8+7]}={ci[g],co[g]};
 end
 repeat(5)@(negedge clk);rst=1;@(negedge sc);sv=1;@(negedge sc);sv=0;
 for(f=0;f<7;f=f+1)begin
  for(y=0;y<H;y=y+1)begin
   for(x=0;x<W;x=x+1)begin
    @(negedge clk);req={2'b00,1'b1,(x==0 && y==0),(x==W-1)};{dx,dy,src}={x,y,pixel(x,y)};
    if(f==0 && y==80 && x==200)en=1;
    if(f==5 && y==80 && x==200)en=0;
   end
   @(negedge clk);{req,src}=29'd0;repeat(3)@(negedge clk);
  end
  @(negedge clk);{req,src}=29'd0;repeat(49500)@(negedge clk);
  if(f==5)begin
   checks=checks+1;if(dut.S_cal_regions_valid!==1)begin errors=errors+1;$display("FAIL nine patch valid");end
   for(g=0;g<9;g=g+1)begin
    for(c=0;c<3;c=c+1)begin
     if(dut.S_cal_regions_in[g*24+16-c*8+:8]!==ex[g*8+c][7:0] || dut.S_cal_regions_out[g*24+16-c*8+:8]!==ex[g*8+c+3][7:0])begin errors=errors+1;$display("FAIL patch%0d channel%0d got IN%h OUT%h expected%0d,%0d",g,c,dut.S_cal_regions_in[g*24+16-c*8+:8],dut.S_cal_regions_out[g*24+16-c*8+:8],ex[g*8+c],ex[g*8+c+3]);end
    end
    if(dut.S_cal_regions_clip_in[g*13+:13]!==ci[g][12:0] || dut.S_cal_regions_clip_out[g*13+:13]!==co[g][12:0])begin errors=errors+1;$display("FAIL patch clip%0d",g);end
   end
   if(dut.S_awb_status!==sd || dut.u_hdmi_mixer.g_regions.u_cal_osd.awb_s!==sd)begin errors=errors+1;$display("FAIL real CDC status snapshot");end
   if(dut.u_hdmi_mixer.g_regions.u_cal_osd.digits[74]!==16'h0512 || dut.u_hdmi_mixer.g_regions.u_cal_osd.digits[75]!==16'h0128 || dut.u_hdmi_mixer.g_regions.u_cal_osd.digits[76]!==16'h1024)begin errors=errors+1;$display("FAIL status final77 fields");end
   for(i=0;i<72;i=i+1)begin
    value=ex[i];expected_bcd=(value/1000)*4096+((value/100)%10)*256+((value/10)%10)*16+value%10;
    if(dut.u_hdmi_mixer.g_regions.u_cal_osd.digits[i]!==expected_bcd[15:0])begin errors=errors+1;$display("FAIL OSD field%0d %h/%h",i,dut.u_hdmi_mixer.g_regions.u_cal_osd.digits[i],expected_bcd);end
   end
  end
  if(f==6 && (dut.S_cal_regions_valid!==0 || dut.u_hdmi_mixer.g_regions.u_cal_osd.en_s!==0))begin errors=errors+1;$display("FAIL SW4 disable");end
 end
 if(osd_pixels==0)begin errors=errors+1;$display("FAIL BC consumer vacuous");end
 test_done=1;if(errors==0)$display("PASS spatial_path checks=%0d pixels=%0d actual_top LSC1 GEOMETRY1 MULTIPOINT1 nineprepost mean_clip OSD77fields actualCDC async BC_consumer toggle timing32 RGB_source+3",checks,pixels);else $display("FAIL spatial_path errors=%0d",errors);$finish;
end
endmodule
