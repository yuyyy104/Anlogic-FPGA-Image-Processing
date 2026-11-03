`timescale 1ns/1ps
module tb_geometry_publish;
reg clk=0,rst=0,de=0,user=0,last=0;always #5 clk=~clk;
reg [23:0] rgb=0,image[0:320*256-1];wire valid;wire [1:0] cls;wire [2:0] why;wire [23:0] fid;wire [19:0] area;wire [11:0] x0,x1,y0,y1;
detect_shape #(.H_ACTIVE(320),.V_ACTIVE(256),.GEOMETRY(1),.TRACK_BOX(1)) dut(.clk(clk),.rst_n(rst),.rgb_in(rgb),.de(de),.user(user),.last(last),.res_valid(valid),.res_cls(cls),.res_reason(why),.res_area(area),.res_xmin(x0),.res_xmax(x1),.res_ymin(y0),.res_ymax(y1),.res_frame_id(fid));
integer mode,x,y,n,errors=0,checks=0;reg test_done=0;reg [67:0] geometry;
initial begin
 $readmemh("D:/codex_project/FPGA_competiton/src/sim/fixtures/shape_geometry/05.mem",image);
 for(mode=0;mode<3;mode=mode+1)begin
  @(negedge clk);rst=0;de=0;user=0;last=0;repeat(3)@(negedge clk);rst=1;
  for(y=0;y<256;y=y+1)for(x=0;x<320;x=x+1)begin @(negedge clk);de=1;user=x==0&&y==0;last=x==319;rgb=image[y*320+x];end
  @(negedge clk);de=0;user=0;last=0;rgb=0;n=0;
  while(dut.g_edges.edges.state!=23 && n<20000)begin @(negedge clk);n=n+1;end
  if(n>=20000)begin errors=errors+1;$display("FAIL publish setup timeout");end
  if(mode>0)@(negedge clk);
  if(mode>1)@(negedge clk);
  user=1;de=1;rgb=24'h303030;
  @(posedge clk);#1;checks=checks+1;
  if(!valid || fid!==0 || cls!==(mode<2?2'd3:2'd2) || why!==(mode<2?3'd5:3'd0))begin errors=errors+1;$display("FAIL publish boundary mode%0d ready%b cls%0d why%0d fid%0d",mode,dut.geom_ready,cls,why,fid);end
  if(mode==0)geometry={area,x0,x1,y0,y1};else if({area,x0,x1,y0,y1}!==geometry)begin errors=errors+1;$display("FAIL publication mixed geometry");end
 end
 test_done=1;if(errors==0)$display("PASS geometry_publish ready_same_plus1_plus2 atomic_bbox_area_fid UNKNOWN5_UNKNOWN5_RECT0 checks%0d",checks);else $display("FAIL geometry_publish errors%0d",errors);$finish;
end
endmodule
