`timescale 1ns/1ps
// A shared bounded contour classifier for a captured 4-pixel palette grid.
// Output class IDs: 1 sphere, 2 cube, 5 unknown. A sphere is accepted from a
// circular contour; a cube is accepted from a straight-sided quadrilateral or
// projected hexagonal outline. Triangles and ambiguous contours stay unknown.
module shape_polygon #(parameter GRID_H=180, parameter integer MIN_BBOX=24)(
 input clk,rst_n,clear,row_write,row_valid,finish,
 input [7:0] row_y,input [11:0] row_left,row_right,row_points,bbox_w,bbox_h,
 input [19:0] area,output reg ready,output reg [2:0] shape
);
 localparam AW=$clog2(GRID_H);
 reg [11:0] ex[0:7],ey[0:7];
 reg signed [13:0] metric[0:7];reg [8:0] order[0:7];reg captured;
 reg [3:0] count,original_count,index,sort_j,edge_index,best_index;
 reg [7:0] sort_used;reg sort_found;reg [8:0] best_order;
 reg [6:0] state;reg [7:0] scan_y;reg side;
 // Captured 1280x720 coordinates bound the minimum side to 720;
 // max(4,min_side/32) therefore fits five bits.
 reg [11:0] px,py;reg [4:0] tolerance;reg small_target;reg [19:0] frozen_area;
 wire [4:0] verify_tolerance=small_target?(count==4?5'd1:5'd2):tolerance;
 reg [12:0] edge_length;reg [8:0] edge_hits,edge_total,edge_middle;
 reg [12:0] edge_near,edge_far;reg all_edges_ok;
 reg signed [12:0] ml0,mr0,ml1,mr1;
 reg signed [25:0] product0,product1;
 reg signed [27:0] area_sum;reg [27:0] polygon2;
 reg [26:0] min_length2,max_length2;reg [23:0] bbox_area;reg [15:0] perimeter;
 reg [24:0] error_limit;reg [12:0] distance;
 reg [4:0] limit_tolerance;reg [12:0] limit_length;
 reg segment,in_range,any_match;reg [9:0] contour_points,good_points;
 wire [30:0] row_packet;
 wire [35:0] row_data={row_packet[30:21],2'b00,row_packet[20:11],2'b00,3'b000,row_packet[10:2]};
 reg [1:0] matched_row;reg write_match;
 PH1P_LOGIC_ERAM #(.DATA_WIDTH_A(31),.DATA_WIDTH_B(31),.ADDR_WIDTH_A(AW),.ADDR_WIDTH_B(AW),
  .DATA_DEPTH_A(GRID_H),.DATA_DEPTH_B(GRID_H),.BYTE_ENABLE(0),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG")) rows(
  .clka(clk),.cea(1'b1),.ocea(1'b0),.wea(rst_n && (row_write || write_match)),.addra(row_write?row_y[AW-1:0]:scan_y[AW-1:0]),
  .dia(row_write?(row_valid?{row_left[11:2],row_right[11:2],row_points[8:0],2'b00}:31'd0):{row_packet[30:2],matched_row}),.rsta(1'b0),.bea(1'b1),.doa(),
  .clkb(clk),.ceb(state==30),.oceb(1'b1),.web(1'b0),.addrb(scan_y[AW-1:0]),.dib(31'd0),.rstb(1'b0),.beb(1'b1),.dob(row_packet),
  .ecc_sbiterrinj(1'b0),.ecc_dbiterrinj(1'b0),.ecc_sbiterr(),.ecc_dbiterr());
 reg vertex_we;reg [2:0] vertex_wa,vertex_ra;reg [32:0] vertex_wd;
 wire [32:0] vertex_rd;
 reg [32:0] vertex_previous,vertex_current,vertex_next,edge_a,edge_b,first_vertex,last_vertex;
 reg verify_phase;
 PH1P_LOGIC_ERAM #(.DATA_WIDTH_A(33),.DATA_WIDTH_B(33),.ADDR_WIDTH_A(3),.ADDR_WIDTH_B(3),
  .DATA_DEPTH_A(8),.DATA_DEPTH_B(8),.BYTE_ENABLE(0),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG")) vertices(
  .clka(clk),.cea(1'b1),.ocea(1'b0),.wea(rst_n && vertex_we),.addra(vertex_wa),.dia(vertex_wd),.rsta(1'b0),.bea(1'b1),.doa(),
  .clkb(clk),.ceb(1'b1),.oceb(1'b1),.web(1'b0),.addrb(vertex_ra),.dib(33'd0),.rstb(1'b0),.beb(1'b1),.dob(vertex_rd),
  .ecc_sbiterrinj(1'b0),.ecc_dbiterrinj(1'b0),.ecc_sbiterr(),.ecc_dbiterr());
 wire [11:0] pvx=vertex_previous[32:21],pvy=vertex_previous[20:9];
 wire [11:0] cvx=vertex_current[32:21],cvy=vertex_current[20:9];
 wire [11:0] nvx=vertex_next[32:21],nvy=vertex_next[20:9];
 wire [11:0] avx=edge_a[32:21],avy=edge_a[20:9],bvx=edge_b[32:21],bvy=edge_b[20:9];
 wire [8:0] ao=edge_a[8:0],bo=edge_b[8:0];
 wire [12:0] average_x={1'b0,cvx}+{1'b0,nvx},average_y={1'b0,cvy}+{1'b0,nvy};
 wire [9:0] average_order={1'b0,vertex_current[8:0]}+{1'b0,vertex_next[8:0]};
 wire [32:0] average_vertex={average_x[12:1],average_y[12:1],average_order[9:1]};
 function signed [13:0] support;
 input integer i;input [11:0] l,r,y;
 begin case(i)
  0:support=-$signed({2'b0,l});1:support=-$signed({2'b0,y});
  2:support=$signed({2'b0,r});3:support=$signed({2'b0,y});
  4:support=-$signed({2'b0,l})-$signed({2'b0,y});
  5:support=$signed({2'b0,r})-$signed({2'b0,y});
  6:support=$signed({2'b0,r})+$signed({2'b0,y});
  default:support=$signed({2'b0,y})-$signed({2'b0,l});endcase end
 endfunction
 function [12:0] magnitude;
 input signed [12:0] v;begin magnitude=v<0?-v:v;end
 endfunction
 wire [3:0] next_index=index+1>=count?4'd0:index+1'b1;
 wire [3:0] previous_index=index==0?count-1'b1:index-1'b1;
 wire [3:0] next_edge=edge_index+1>=count?4'd0:edge_index+1'b1;
 wire signed [26:0] cross=$signed({product0[25],product0})-$signed({product1[25],product1});
 wire [26:0] abs_cross=cross<0?-cross:cross;
 wire signed [12:0] edge_dx=$signed({1'b0,bvx})-$signed({1'b0,avx});
 wire signed [12:0] edge_dy=$signed({1'b0,bvy})-$signed({1'b0,avy});
 wire signed [12:0] qx=$signed({1'b0,px})-$signed({1'b0,avx});
 wire signed [12:0] qy=$signed({1'b0,py})-$signed({1'b0,avy});
 // The second product is prepared one state earlier; both products still
 // reach the original consume state, with one shared registered multiplier.
 wire second_product=state==76 || state==12 || state==14 || state==32;
 wire signed [12:0] multiply_left=second_product?ml1:ml0;
 wire signed [12:0] multiply_right=second_product?mr1:mr0;
 wire signed [25:0] multiplied=multiply_left*multiply_right;
 wire [8:0] point_order=side?2*GRID_H-1-scan_y:{1'b0,scan_y};
 wire edge_match=segment && in_range && abs_cross<=error_limit;
 wire edge_ok=edge_length>=12 && edge_hits>=2 && edge_middle>=1 &&
  (small_target?edge_hits*10>=edge_total*9:{edge_hits,2'b00}>=edge_total*3) &&
  (edge_far-edge_near)*2>=edge_length;
 wire polygon_area_ok={good_points,2'b00}>=contour_points*3 && polygon2!=0 && {frozen_area,2'b00}>=polygon2 &&
  {frozen_area,4'b0000}<=(polygon2<<3)+polygon2+({12'd0,perimeter}<<5)+28'd256;
 wire polygon_outline=count>=4 && all_edges_ok && polygon_area_ok;
 wire sphere_outline=count>=5 && original_count>=5 && {frozen_area,4'b0000}>=bbox_area*9 &&
  {frozen_area,4'b0000}<=bbox_area*15 && bbox_w<=2*bbox_h && bbox_h<=2*bbox_w;
 integer i;reg [11:0] sx,source_y;reg [8:0] so;
 reg signed [12:0] dx,dy,tx,ty;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=0;ready<=0;shape<=5;captured<=0;count<=0;original_count<=0;index<=0;sort_j<=0;edge_index<=0;sort_used<=0;sort_found<=0;best_index<=0;best_order<=511;
   edge_length<=0;edge_hits<=0;edge_total<=0;edge_middle<=0;edge_near<=8191;edge_far<=0;all_edges_ok<=0;
   scan_y<=0;side<=0;px<=0;py<=0;tolerance<=4;small_target<=0;frozen_area<=0;matched_row<=0;write_match<=0;
   vertex_we<=0;vertex_wa<=0;vertex_ra<=0;vertex_wd<=0;verify_phase<=0;
   {vertex_previous,vertex_current,vertex_next,edge_a,edge_b,first_vertex,last_vertex}<=0;
   ml0<=0;mr0<=0;ml1<=0;mr1<=0;product0<=0;product1<=0;area_sum<=0;polygon2<=0;
   min_length2<=27'h7ffffff;max_length2<=0;bbox_area<=0;perimeter<=0;error_limit<=0;distance<=0;limit_tolerance<=0;limit_length<=0;
   segment<=0;in_range<=0;any_match<=0;contour_points<=0;good_points<=0;
   for(i=0;i<8;i=i+1)begin ex[i]<=0;ey[i]<=0;metric[i]<=-8192;order[i]<=0;end
  end else if(clear)begin state<=0;ready<=0;shape<=5;captured<=0;write_match<=0;vertex_we<=0;for(i=0;i<8;i=i+1)metric[i]<=-8192;end
  else begin
   write_match<=0;vertex_we<=0;
   if(second_product)product1<=multiplied;else product0<=multiplied;
   error_limit<=limit_tolerance*limit_length;
   if(row_write && row_valid)begin
    source_y={2'd0,row_y,2'b00};
    for(i=0;i<8;i=i+1)begin
     sx=(i==0 || i==1 || i==4 || i==7)?row_left:row_right;
     so=(i==0 || i==1 || i==4 || i==7)?{1'b0,row_y}:2*GRID_H-1-row_y;
     if(!captured || support(i,row_left,row_right,source_y)>metric[i] ||
       (support(i,row_left,row_right,source_y)==metric[i] && so<order[i]))begin
      ex[i]<=sx;ey[i]<=source_y;metric[i]<=support(i,row_left,row_right,source_y);order[i]<=so;
     end
    end
    captured<=1;
   end
   case(state)
    0:if(finish)begin
     ready<=0;shape<=5;frozen_area<=area;tolerance<=(bbox_w<bbox_h?bbox_w:bbox_h)<128?12'd4:(bbox_w<bbox_h?bbox_w:bbox_h)>>5;
     small_target<=bbox_w<48 && bbox_h<48;
     ml0<=$signed({1'b0,bbox_w});mr0<=$signed({1'b0,bbox_h});ml1<=0;mr1<=0;
     if(!captured || bbox_w<MIN_BBOX || bbox_h<MIN_BBOX)begin ready<=1;state<=60;end
     else begin sort_j<=0;sort_used<=0;sort_found<=0;best_order<=511;count<=0;state<=1;end
    end
    // Select one support point at a time. One vertex write per cycle
    // allows a small memory instead of an eight-way dual-write register mux.
    1:begin
     if(!sort_used[sort_j] && (!sort_found || order[sort_j]<best_order))begin
      best_index<=sort_j;best_order<=order[sort_j];sort_found<=1;
     end
     if(sort_j==7)state<=2;else sort_j<=sort_j+1'b1;
    end
    2:begin
     if(!sort_found)begin bbox_area<=product0;state<=3;end
     else begin
      sort_used[best_index]<=1;
      if(count==0 || last_vertex[32:21]!=ex[best_index] || last_vertex[20:9]!=ey[best_index])begin
       vertex_we<=1;vertex_wa<=count[2:0];vertex_wd<={ex[best_index],ey[best_index],order[best_index]};
       last_vertex<={ex[best_index],ey[best_index],order[best_index]};
       if(count==0)first_vertex<={ex[best_index],ey[best_index],order[best_index]};
       count<=count+1'b1;
      end
      sort_j<=0;sort_found<=0;best_order<=511;state<=1;
     end
    end
    3:begin
     if(count>1 && first_vertex[32:9]==last_vertex[32:9])count<=count-1'b1;
     original_count<=count;
     index<=0;state<=4;
    end
    // Remove redundant support points on straight edges; keep real corners.
    4:begin
     if(count<3)begin shape<=5;ready<=1;state<=60;end
     else if(index>=count || count==3)begin edge_index<=0;area_sum<=0;perimeter<=0;min_length2<=27'h7ffffff;max_length2<=0;verify_phase<=0;state<=9;end
     else begin vertex_ra<=previous_index[2:0];state<=70;end
    end
    70:state<=71;
    71:begin vertex_previous<=vertex_rd;vertex_ra<=index[2:0];state<=72;end
    72:state<=73;
    73:begin vertex_current<=vertex_rd;vertex_ra<=next_index[2:0];state<=74;end
    74:state<=75;
    75:begin
     vertex_next<=vertex_rd;
     ml1<=$signed({1'b0,cvy})-$signed({1'b0,pvy});
     mr1<=$signed({1'b0,vertex_rd[32:21]})-$signed({1'b0,pvx});
     state<=76;
    end
    76:begin
      dx=$signed({1'b0,nvx})-$signed({1'b0,pvx});
      dy=$signed({1'b0,nvy})-$signed({1'b0,pvy});
      tx=$signed({1'b0,cvx})-$signed({1'b0,pvx});
      ty=$signed({1'b0,cvy})-$signed({1'b0,pvy});
      ml0<=tx;mr0<=dy;limit_tolerance<=small_target?5'd2:tolerance;limit_length<=magnitude(dx)+magnitude(dy);
      in_range<=cvx+tolerance>=(pvx<nvx?pvx:nvx) &&
       cvx<=(pvx>nvx?pvx:nvx)+tolerance &&
       cvy+tolerance>=(pvy<nvy?pvy:nvy) &&
       cvy<=(pvy>nvy?pvy:nvy)+tolerance;
      state<=5;
    end
    5:state<=6;
    6:begin
     if(in_range && abs_cross<=error_limit)state<=7;
     else if(count>4 && next_index!=0 &&
       (magnitude($signed({1'b0,nvx})-$signed({1'b0,cvx}))+
        magnitude($signed({1'b0,nvy})-$signed({1'b0,cvy})))*4<=
       magnitude($signed({1'b0,cvx})-$signed({1'b0,pvx}))+
       magnitude($signed({1'b0,cvy})-$signed({1'b0,pvy})))begin
      vertex_we<=1;vertex_wa<=index[2:0];vertex_wd<=average_vertex;
      index<=next_index;state<=7;
     end else begin index<=index+1'b1;state<=4;end
    end
    7:begin
     if(index+1<count)begin vertex_ra<=index+1'b1;state<=80;end
     else begin count<=count-1'b1;index<=0;state<=4;end
    end
    80:state<=81;
    81:begin vertex_we<=1;vertex_wa<=index[2:0];vertex_wd<=vertex_rd;index<=index+1'b1;state<=7;end
    9:begin vertex_ra<=edge_index[2:0];state<=10;end
    10:state<=11;
    11:begin edge_a<=vertex_rd;vertex_ra<=next_edge[2:0];state<=17;end
    17:state<=18;
    18:begin edge_b<=vertex_rd;ml1<=$signed({1'b0,avy});mr1<=$signed({1'b0,vertex_rd[32:21]});state<=verify_phase?20:12;end
    12:begin
     ml0<=$signed({1'b0,avx});mr0<=$signed({1'b0,bvy});
     perimeter<=perimeter+magnitude(edge_dx)+magnitude(edge_dy);
     state<=13;
    end
    13:begin ml1<=edge_dy;mr1<=edge_dy;state<=14;end
    14:begin area_sum<=area_sum+cross;ml0<=edge_dx;mr0<=edge_dx;state<=15;end
    15:state<=16;
    16:begin
     if($signed({product0[25],product0})+$signed({product1[25],product1})<min_length2)min_length2<=product0+product1;
     if($signed({product0[25],product0})+$signed({product1[25],product1})>max_length2)max_length2<=product0+product1;
     if(edge_index+1==count)begin polygon2<=area_sum<0?-area_sum:area_sum;edge_index<=0;all_edges_ok<=1;contour_points<=0;good_points<=0;verify_phase<=1;state<=9;end
     else begin edge_index<=edge_index+1'b1;state<=9;end
    end
    // Verify each contour interval on its own side with shared counters.
    // Sorted vertex orders partition the complete L-down/R-up contour.
    20:begin
     edge_length<=magnitude(edge_dx)+magnitude(edge_dy);edge_hits<=0;edge_total<=0;edge_middle<=0;edge_near<=8191;edge_far<=0;
     scan_y<=0;state<=30;
    end
    30:state<=31;
    31:if(row_data[11:0]==0)state<=40;else begin
     px<=row_data[35:24];py<={2'd0,scan_y,2'b00};side<=0;matched_row<=row_packet[1:0];
     ml1<=$signed({1'b0,2'd0,scan_y,2'b00})-$signed({1'b0,avy});mr1<=edge_dx;
     if(edge_index==0)contour_points<=contour_points+2;
     state<=32;
    end
    32:begin
     segment<=ao<=bo?
       point_order>=ao && point_order<=bo:
       point_order>=ao || point_order<=bo;
     ml0<=qx;mr0<=edge_dy;limit_tolerance<=verify_tolerance;limit_length<=edge_length;
     distance<=magnitude(qx)+magnitude(qy);
     in_range<=px+verify_tolerance>=(avx<bvx?avx:bvx) &&
      px<=(avx>bvx?avx:bvx)+verify_tolerance &&
      py+verify_tolerance>=(avy<bvy?avy:bvy) &&
      py<=(avy>bvy?avy:bvy)+verify_tolerance;
     state<=33;
    end
    33:state<=34;
    34:begin
     if(edge_match)begin
      edge_hits<=edge_hits+1'b1;
      if(!matched_row[side])good_points<=good_points+1'b1;
      matched_row[side]<=1;
      if(({distance,2'b00}>=edge_length && {distance,2'b00}<=edge_length*3) ||
         (avy==bvy &&
          {row_data[11:0],3'b000}>=row_data[23:12]-row_data[35:24] &&
          {1'b0,row_data[35:24],1'b0}<=avx+bvx &&
          {1'b0,row_data[23:12],1'b0}>=avx+bvx))
       edge_middle<=edge_middle+1'b1;
      if(distance<edge_near)edge_near<=distance;
      if(distance>edge_far)edge_far<=distance;
     end
     // Judge each L-down/R-up interval on its own straight side.
     if(segment)edge_total<=edge_total+1'b1;
     state<=35;
    end
    35:begin
     write_match<=1;
     if(!side)begin px<=row_data[23:12];side<=1;state<=32;end
     else state<=40;
    end
    40:if(scan_y==GRID_H-1)state<=42;else begin scan_y<=scan_y+1'b1;state<=30;end
    42:begin
     all_edges_ok<=all_edges_ok && edge_ok;
     if(edge_index+1==count)state<=41;else begin edge_index<=edge_index+1'b1;state<=9;end
    end
    41:begin
     // Four-sided objects and six-sided perspective silhouettes have straight
     // support edges. Circles do not satisfy the same row-envelope check.
     if(polygon_outline && original_count<=6)shape<=2;
     else if(sphere_outline)shape<=1;
     else shape<=5;
     ready<=1;state<=60;
    end
    default:;
   endcase
  end
 end
endmodule
