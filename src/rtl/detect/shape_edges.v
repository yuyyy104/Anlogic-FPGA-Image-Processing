`timescale 1ns/1ps
// Two four-corner support candidates, verified against every real row envelope.
// One row RAM; shared three multipliers operate only during vertical blanking.
// Completion <= 56*V_ACTIVE+200 clocks. New user cancels incomplete work.
module shape_edges #(parameter H_ACTIVE=1280,V_ACTIVE=720)(
 input clk,rst_n,user,row_write,row_valid,finish,
 input [11:0] row_y,row_left,row_right,row_points,bbox_w,bbox_h,
 input [19:0] area,
 output reg ready,rectangle
);
 localparam AW=$clog2(V_ACTIVE);
 reg [11:0] ex[0:7],ey[0:7];reg signed [13:0] metric[0:7];
 reg [12:0] order[0:7];reg captured;
 reg [12:0] length[0:7];reg [10:0] totals[0:7],hits[0:7],middle[0:7];
 reg [12:0] near_d[0:7],far_d[0:7];reg [23:0] quad2[0:1];
 reg [19:0] frozen_area;reg [11:0] tolerance;
 reg [10:0] point_count,good0,good1;
 reg [5:0] state;reg [2:0] edge_idx,sort_i,sort_j;reg [11:0] scan_y;
 reg side;reg [11:0] px,py;reg any0,any1;
 reg signed [25:0] mul_a,mul_b;reg [24:0] error_limit;
 reg signed [12:0] ml0,mr0,ml1,mr1;
 wire signed [26:0] cross=$signed({mul_a[25],mul_a})-$signed({mul_b[25],mul_b});
 reg [12:0] distance;reg in_range,segment;
 reg signed [27:0] area_sum;
 wire [35:0] row_data;
 PH1P_LOGIC_ERAM #(.DATA_WIDTH_A(36),.DATA_WIDTH_B(36),.ADDR_WIDTH_A(AW),.ADDR_WIDTH_B(AW),
  .DATA_DEPTH_A(V_ACTIVE),.DATA_DEPTH_B(V_ACTIVE),.BYTE_ENABLE(0),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG")) rows(
  .clka(clk),.cea(1'b1),.ocea(1'b0),.wea(rst_n && row_write),.addra(row_y[AW-1:0]),
  .dia(row_valid?{row_left,row_right,row_points}:36'd0),.rsta(1'b0),.bea(1'b1),.doa(),
  .clkb(clk),.ceb(state==12),.oceb(1'b1),.web(1'b0),.addrb(scan_y[AW-1:0]),.dib(36'd0),.rstb(1'b0),.beb(1'b1),.dob(row_data),
  .ecc_sbiterrinj(1'b0),.ecc_dbiterrinj(1'b0),.ecc_sbiterr(),.ecc_dbiterr());
 function signed [13:0] support;
 input integer i;input [11:0] l,r,y;
 begin case(i)
  0:support=-$signed({2'b0,l});1:support=-$signed({2'b0,y});
  2:support=$signed({2'b0,r});3:support=$signed({2'b0,y});
  4:support=-$signed({2'b0,l})-$signed({2'b0,y});
  5:support=$signed({2'b0,r})-$signed({2'b0,y});
  6:support=$signed({2'b0,r})+$signed({2'b0,y});
  default:support=$signed({2'b0,y})-$signed({2'b0,l});endcase
 end endfunction
 function [12:0] magnitude;
 input signed [12:0] v;begin magnitude=v<0?-v:v;end
 endfunction
 wire [2:0] next_edge={edge_idx[2],edge_idx[1:0]+2'd1};
 wire [11:0] ax=ex[edge_idx],ay=ey[edge_idx],bx=ex[next_edge],by=ey[next_edge];
 wire [12:0] start_order=order[edge_idx],end_order=order[next_edge];
 wire signed [12:0] dx=$signed({1'b0,bx})-$signed({1'b0,ax});
 wire signed [12:0] dy=$signed({1'b0,by})-$signed({1'b0,ay});
 wire signed [12:0] qx=$signed({1'b0,px})-$signed({1'b0,ax});
 wire signed [12:0] qy=$signed({1'b0,py})-$signed({1'b0,ay});
 wire [26:0] abs_cross=cross<0?-cross:cross;
 wire match_edge=segment && in_range && abs_cross<=error_limit;
 wire [12:0] contour_order=side?2*V_ACTIVE-1-py:{1'b0,py};
 wire mid_edge=match_edge && {distance,2'b0}>=length[edge_idx] && {distance,2'b0}<=3*{2'b0,length[edge_idx]};
 reg [1:0] pass_candidate;
 integer k;
 always @(*) begin
  pass_candidate=2'b11;
  for(k=0;k<8;k=k+1)
   if(length[k]<16 || totals[k]<2 || hits[k]*4<totals[k]*3 || middle[k]<2 ||
      (far_d[k]-near_d[k])*2<length[k]) pass_candidate[k/4]=0;
  for(k=0;k<2;k=k+1)
   if(quad2[k]==0 || {frozen_area,2'b0}<quad2[k] ||
      {frozen_area,4'b0}>({4'b0,quad2[k]}<<3)+{4'b0,quad2[k]}) pass_candidate[k]=0;
  if(good0*4<point_count*3)pass_candidate[0]=0;
  if(good1*4<point_count*3)pass_candidate[1]=0;
 end
 integer i;reg [11:0] sx;reg [12:0] so;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   ready<=0;rectangle<=0;state<=0;captured<=0;scan_y<=0;side<=0;edge_idx<=0;
   sort_i<=0;sort_j<=0;frozen_area<=0;tolerance<=0;point_count<=0;good0<=0;good1<=0;
   px<=0;py<=0;any0<=0;any1<=0;mul_a<=0;mul_b<=0;ml0<=0;mr0<=0;ml1<=0;mr1<=0;error_limit<=0;distance<=0;in_range<=0;segment<=0;area_sum<=0;
   for(i=0;i<8;i=i+1) begin
    ex[i]<=0;ey[i]<=0;metric[i]<=-8192;order[i]<=0;
    length[i]<=0;totals[i]<=0;hits[i]<=0;middle[i]<=0;near_d[i]<=8191;far_d[i]<=0;
   end
   quad2[0]<=0;quad2[1]<=0;
  end else if(user) begin
   // Each frame either completed its own scan or publishes UNKNOWN upstream.
   state<=0;captured<=0;ready<=0;rectangle<=0;
   for(i=0;i<8;i=i+1)metric[i]<=-8192;
  end else begin
   if(row_write && row_valid) begin
    for(i=0;i<8;i=i+1) begin
     sx=(i==0 || i==1 || i==4 || i==7)?row_left:row_right;
     so=(i==0 || i==1 || i==4 || i==7)?{1'b0,row_y}:2*V_ACTIVE-1-row_y;
     if(!captured || support(i,row_left,row_right,row_y)>metric[i] ||
        (support(i,row_left,row_right,row_y)==metric[i] && so<order[i])) begin
      ex[i]<=sx;ey[i]<=row_y;metric[i]<=support(i,row_left,row_right,row_y);order[i]<=so;
     end
    end
    captured<=1;
   end
   mul_a<=ml0*mr0;mul_b<=ml1*mr1;
   case(state)
    0:if(finish) begin
     ready<=0;rectangle<=0;frozen_area<=area;
     tolerance<=(bbox_w<bbox_h?bbox_w:bbox_h)<96?12'd3:(bbox_w<bbox_h?bbox_w:bbox_h)>>5;
     if(!captured || bbox_w<32 || bbox_h<32) begin ready<=1;state<=25;end
     else begin
      sort_i<=0;sort_j<=0;state<=1;
     end
    end
    // Sort each four-point candidate into L-down / R-up contour order.
    1:begin
     if(order[sort_j]>order[sort_j+1'b1]) begin
      ex[sort_j]<=ex[sort_j+1'b1];ey[sort_j]<=ey[sort_j+1'b1];order[sort_j]<=order[sort_j+1'b1];
      ex[sort_j+1'b1]<=ex[sort_j];ey[sort_j+1'b1]<=ey[sort_j];order[sort_j+1'b1]<=order[sort_j];
     end
     if(sort_j==2 || sort_j==6) begin
      if(sort_i==5)begin edge_idx<=0;area_sum<=0;state<=2;end
      else begin sort_i<=sort_i+1'b1;sort_j<=sort_i<2?0:4;end
     end else sort_j<=sort_j+1'b1;
    end
    2:begin
     ml0<=$signed({1'b0,ax});mr0<=$signed({1'b0,by});ml1<=$signed({1'b0,ay});mr1<=$signed({1'b0,bx});
     totals[edge_idx]<=0;hits[edge_idx]<=0;middle[edge_idx]<=0;near_d[edge_idx]<=8191;far_d[edge_idx]<=0;
     state<=3;
    end
    3:begin
     length[edge_idx]<=magnitude(dx)+magnitude(dy);
     state<=4;
    end
    4:begin area_sum<=area_sum+$signed({mul_a[25],mul_a})-$signed({mul_b[25],mul_b});state<=5;end
    5:begin
     if(edge_idx[1:0]==3)begin quad2[edge_idx[2]]<=area_sum<0?-area_sum:area_sum;area_sum<=0;end
     if(edge_idx==7)begin scan_y<=0;point_count<=0;good0<=0;good1<=0;state<=12;end
     else begin edge_idx<=edge_idx+1'b1;state<=2;end
    end
    12:state<=13;
    13:begin
     if(row_data[11:0]==0)state<=22;
     else begin px<=row_data[35:24];py<=scan_y;side<=0;edge_idx<=0;any0<=0;any1<=0;state<=14;end
    end
    14:begin
     segment<=start_order<=end_order?
              contour_order>=start_order && contour_order<=end_order:
              contour_order>=start_order || contour_order<=end_order;
     ml0<=qx;mr0<=dy;ml1<=qy;mr1<=dx;error_limit<=tolerance*length[edge_idx];
     distance<=magnitude(qx)+magnitude(qy);
     in_range<=px+tolerance>=(ax<bx?ax:bx) &&
              px<=(ax>bx?ax:bx)+tolerance &&
              py+tolerance>=(ay<by?ay:by) &&
              py<=(ay>by?ay:by)+tolerance;
     state<=15;
    end
    15:state<=16;
    16:begin
     // Assign the L-down/R-up contour interval to its own edge. An opposite
     // side sharing the bounding extent must not dilute straight-edge support.
     if(segment)totals[edge_idx]<=totals[edge_idx]+1'b1;
     if(match_edge) begin
      hits[edge_idx]<=hits[edge_idx]+1'b1;
      if(mid_edge)middle[edge_idx]<=middle[edge_idx]+1'b1;
      if(distance<near_d[edge_idx])near_d[edge_idx]<=distance;
      if(distance>far_d[edge_idx])far_d[edge_idx]<=distance;
      if(edge_idx[2])any1<=1;else any0<=1;
     end
     if(edge_idx==7)state<=17;else begin edge_idx<=edge_idx+1'b1;state<=14;end
    end
    17:begin
     point_count<=point_count+1'b1;if(any0)good0<=good0+1'b1;if(any1)good1<=good1+1'b1;
     if(!side)begin px<=row_data[23:12];side<=1;edge_idx<=0;any0<=0;any1<=0;state<=14;end
     else state<=22;
    end
    22:begin if(scan_y==V_ACTIVE-2)state<=23;else begin scan_y<=scan_y+1'b1;state<=12;end end
    23:begin rectangle<=|pass_candidate;ready<=1;state<=25;end
    default:;
   endcase
  end
 end
endmodule
