`timescale 1ns/1ps
module tb_shape_polygon;
reg clk=0,rst=0,clear=0,write=0,finish=0;always #5 clk=~clk;
reg [7:0] y=0;reg [11:0] l=0,r=0,points=0;reg [19:0] area=0;
reg [11:0] bw=92,bh=92;
wire ready;wire [2:0] shape;integer errors=0,checks=0,case_id,row,m,k;reg test_done=0;
shape_polygon #(.GRID_H(64)) dut(.clk(clk),.rst_n(rst),.clear(clear),.row_write(write),.row_valid(points!=0),.finish(finish),
 .row_y(y),.row_left(l),.row_right(r),.row_points(points),.bbox_w(bw),.bbox_h(bh),.area(area),.ready(ready),.shape(shape));
task classify;input [2:0] expected;begin
 finish=1;@(negedge clk);finish=0;k=0;while(!ready && k<20000)begin @(negedge clk);k=k+1;end
 checks=checks+1;if(!ready || shape!==expected)begin errors=errors+1;$display("FAIL polygon boundary case%0d bbox%0d/%0d shape%0d/%0d n%0d original%0d allEdges%0d good%0d/%0d",case_id,bw,bh,shape,expected,dut.count,dut.original_count,dut.all_edges_ok,dut.good_points,dut.contour_points);end
end endtask
initial begin
 repeat(5)@(negedge clk);rst=1;
 for(case_id=0;case_id<2;case_id=case_id+1)begin
  clear=1;@(negedge clk);clear=0;
  for(row=0;row<64;row=row+1)begin
   y=row;write=1;
   if(row<=22)begin m=row<11?row:22-row;l=44-4*m;r=44+4*m;
    if(case_id==1 && (row==3 || row==4 || row==5 || row==15 || row==16 || row==17))begin l=l+12;r=r-12;end
    points=(r-l)/4+1;
   end else begin l=0;r=0;points=0;end
   @(negedge clk);
  end
  write=0;area=case_id==0?20'd4240:20'd3664;finish=1;@(negedge clk);finish=0;k=0;
  while(!ready && k<20000)begin @(negedge clk);k=k+1;end
  checks=checks+1;
  if(!ready || shape!==(case_id==0?3'd2:3'd5))begin errors=errors+1;$display("FAIL concave polygon case%0d shape%0d good%0d/%0d",case_id,shape,dut.good_points,dut.contour_points);end
 end
 for(case_id=0;case_id<5;case_id=case_id+1)begin
  clear=1;@(negedge clk);clear=0;
  bw=case_id<2?(case_id==0?23:24):case_id==2?100:case_id==3?104:108;
  bh=case_id<2?24:84;
  for(row=0;row<64;row=row+1)begin
   y=row;write=1;l=0;r=bw<28?20:bw-4;points=row<bh/4?(r/4+1):0;@(negedge clk);
  end
  write=0;area=(r/4+1)*(bh/4)*16;classify(case_id==0?3'd5:3'd2);
 end
 clear=1;@(negedge clk);clear=0;bw=24;bh=24;
 for(row=0;row<64;row=row+1)begin
  y=row;write=1;
  case(row)0:begin l=8;r=8;end 1:begin l=8;r=12;end 2:begin l=4;r=12;end 3:begin l=4;r=16;end 4:begin l=0;r=16;end 5:begin l=0;r=20;end default:begin l=0;r=0;end endcase
  points=row<6?(r-l)/4+1:0;@(negedge clk);
 end
  write=0;area=336;classify(3'd5);
 test_done=1;if(errors==0)$display("PASS shape_polygon checks%0d cube concave_unknown min_size rectangular_cube small_triangle_unknown",checks);else $display("FAIL shape_polygon errors%0d",errors);$finish;
end
endmodule
