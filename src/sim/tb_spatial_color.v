`timescale 1ns/1ps
module tb_spatial_color;
reg clk=0,rst=0;always #5 clk=~clk;
reg [23:0] rgb=0;reg [4:0] t=0;wire [23:0] actual,aligned,bypass;wire [4:0] ot,bt;
spatial_color on(.clk(clk),.rst_n(rst),.rgb_in(rgb),.timing_in(t),.rgb_out(actual),.input_aligned(aligned),.timing_out(ot));
spatial_color #(.ENABLE(0)) off(.clk(clk),.rst_n(rst),.rgb_in(rgb),.timing_in(t),.rgb_out(bypass),.timing_out(bt));
`include "D:/codex_project/FPGA_competiton/src/sim/spatial_nodes_ref.vh"
reg [23:0] cq[0:6],iq[0:6];reg [4:0] tq[0:6];integer checks=0,errors=0,x=0,y=0,i,a,b,f,n,c,gain,rr,bb;reg test_done=0;
function [23:0] reference;
input [23:0] p;input integer xx,yy;
integer base,fx,fy,r,v,b,j,g[0:2];
begin
 base=(yy/128)*11+xx/128;fx=xx%128;fy=yy%128;
 for(j=0;j<3;j=j+1)g[j]=(gain_node(base,j)*(128-fx)*(128-fy)+gain_node(base+1,j)*fx*(128-fy)+gain_node(base+11,j)*(128-fx)*fy+gain_node(base+12,j)*fx*fy+8192)/16384;
 r=(p[23:16]*g[0]+128)/256;v=(p[15:8]*g[1]+128)/256;b=(p[7:0]*g[2]+128)/256;
 if(r>255)r=255;if(v>255)v=255;if(b>255)b=255;
 reference={r[7:0],v[7:0],b[7:0]};
end endfunction
always @(posedge clk) begin
 if(!rst)begin x=0;y=0;for(i=0;i<7;i=i+1)begin tq[i]<=0;cq[i]<=0;iq[i]<=0;end end
 else begin
  for(i=6;i>0;i=i-1)begin tq[i]<=tq[i-1];cq[i]<=cq[i-1];iq[i]<=iq[i-1];end
  if(t[1])begin x=0;y=0;end
  tq[0]<=t;cq[0]<=reference(rgb,x,y);iq[0]<=rgb;
  if(t[2])begin if(t[0])begin x=0;y=y+1;end else x=x+1;end
  #1;checks=checks+1;
  if(ot!==tq[6] || bt!==tq[6] || actual!==cq[6] || aligned!==iq[6] || bypass!==iq[6])begin
   errors=errors+1;if(errors<8)$display("FAIL spatial %h/%h metadata%b/%b",actual,cq[6],ot,tq[6]);
  end
 end
end
initial begin
 repeat(5)@(negedge clk);rst=1;
 for(f=0;f<2;f=f+1)begin
  for(b=0;b<720;b=b+1)begin
   for(a=0;a<1280;a=a+1)begin
    @(negedge clk);rgb=0;
    // Width-explicit lanes, including dark, bright, clipping and coefficient cell boundaries.
    rgb[23:16]=(a+b)%256;rgb[15:8]=(a*7+b*3)%256;rgb[7:0]=(a*3+b*11)%256;
    t={2'b00,1'b1,(a==0 && b==0),(a==1279)};
   end
   repeat(3)begin @(negedge clk);t=5'b10000;rgb=24'h808080;end
  end
  repeat(17)begin @(negedge clk);t=5'b01000;rgb=24'hff00ff;end
 end
 repeat(10)begin @(negedge clk);t=0;rgb=0;end
 test_done=1;if(errors==0)$display("PASS spatial_color full1280x720 twoframes everypixel gain interpolation rounding clipping timing7 identity_bypass checks=%0d",checks);else $display("FAIL spatial_color errors=%0d",errors);$finish;
end
endmodule
