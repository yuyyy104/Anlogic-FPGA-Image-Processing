`timescale 1ns/1ps
module tb_spatial_path;
localparam W=512,H=256,LAT=32;
reg clk=0,rst=0;always #5 clk=~clk;
reg [23:0] src=0,s1=0,s2=0;reg [4:0] req=0;reg en=0;
wire hv,hh,hd,rd;wire [23:0] out;
p3_display_glue dut(.S_hdmi_pixel_clk(clk),.S_hdmi_rst_n(rst),.S_video_rd_data(s2),
 .S_hdmi_vsync(req[4]),.S_hdmi_hsync(req[3]),.S_hdmi_de(req[2]),.S_hdmi_user(req[1]),.S_hdmi_last(req[0]),
 .S_preproc_mode(4'd0),.S_preproc_thresh(8'd96),.S_hdmi_debug_status(4'b1111),
 .S_cal_stable(en),.S_lock_stable(1'b1),.S_awb_frozen(1'b1),
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
function [23:0] pixel;
input integer xx,yy;
begin
 if(xx>=224 && xx<288 && yy>=96 && yy<160)pixel=24'h998faa;
 else if(xx>=32 && xx<96 && yy<64)pixel=24'h602840;
 else if(xx>=416 && xx<480 && yy<64)pixel=24'h58c889;
 else if(xx>=32 && xx<96 && yy>=192)pixel=24'hd84838;
 else if(xx>=416 && xx<480 && yy>=192)pixel=24'hfae9ff;
 else pixel=24'h606060;
end endfunction
integer sx[0:4],sy[0:4],sum_in[0:14],sum_out[0:14],ci[0:4],co[0:4],ex[0:39];
reg [23:0] pin,pout;integer i,j,x,y,f,k,c,g,expected_bcd,n,value,checks=0,errors=0,pixels=0;
reg test_done=0;reg [4:0] tq[0:LAT-1];integer xq[0:LAT-1],yq[0:LAT-1];
integer dx=0,dy=0,ox,oy;reg [23:0] expected_pixel;
always @(posedge clk)begin
 if(!rst)for(k=0;k<LAT;k=k+1)begin {tq[k],xq[k],yq[k]}<=69'd0;end
 else begin
  {tq[0],xq[0],yq[0]}<={req,dx,dy};
  for(k=1;k<LAT;k=k+1)begin {tq[k],xq[k],yq[k]}<={tq[k-1],xq[k-1],yq[k-1]};end
  #1;checks=checks+1;
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
 {sx[0],sy[0],sx[1],sy[1],sx[2],sy[2],sx[3],sy[3],sx[4],sy[4]}={32'd224,32'd96,32'd32,32'd0,32'd416,32'd0,32'd32,32'd192,32'd416,32'd192};
 for(g=0;g<5;g=g+1)begin
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
 repeat(5)@(negedge clk);rst=1;
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
   checks=checks+1;if(dut.S_cal_regions_valid!==1)begin errors=errors+1;$display("FAIL five patch valid");end
   for(g=0;g<5;g=g+1)begin
    for(c=0;c<3;c=c+1)begin
     if(dut.S_cal_regions_in[g*24+16-c*8+:8]!==ex[g*8+c][7:0] || dut.S_cal_regions_out[g*24+16-c*8+:8]!==ex[g*8+c+3][7:0])begin errors=errors+1;$display("FAIL patch%0d channel%0d got IN%h OUT%h expected%0d,%0d",g,c,dut.S_cal_regions_in[g*24+16-c*8+:8],dut.S_cal_regions_out[g*24+16-c*8+:8],ex[g*8+c],ex[g*8+c+3]);end
    end
    if(dut.S_cal_regions_clip_in[g*13+:13]!==ci[g][12:0] || dut.S_cal_regions_clip_out[g*13+:13]!==co[g][12:0])begin errors=errors+1;$display("FAIL patch clip%0d",g);end
   end
   for(i=0;i<40;i=i+1)begin
    value=ex[i];expected_bcd=(value/1000)*4096+((value/100)%10)*256+((value/10)%10)*16+value%10;
    if(dut.u_hdmi_mixer.g_regions.u_cal_osd.digits[i]!==expected_bcd[15:0])begin errors=errors+1;$display("FAIL OSD field%0d %h/%h",i,dut.u_hdmi_mixer.g_regions.u_cal_osd.digits[i],expected_bcd);end
   end
  end
  if(f==6 && (dut.S_cal_regions_valid!==0 || dut.u_hdmi_mixer.g_regions.u_cal_osd.en_s!==0))begin errors=errors+1;$display("FAIL SW4 disable");end
 end
 test_done=1;if(errors==0)$display("PASS spatial_path checks=%0d pixels=%0d actual_top LSC1 GEOMETRY1 MULTIPOINT1 fiveprepost mean_clip OSD40fields toggle timing32 RGB_source+3",checks,pixels);else $display("FAIL spatial_path errors=%0d",errors);$finish;
end
endmodule
