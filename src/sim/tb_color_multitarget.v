`timescale 1ns/1ps
module tb_color_multitarget;
`ifdef COLOR_HD
localparam W=1280,H=720;
`else
localparam W=512,H=256;
`endif
reg clk=0,rst=0;always #5 clk=~clk;
reg [23:0] rgb=0;reg [4:0] t=0;wire valid,overflow;wire [7:0] count;
wire [11:0] colors,shapes;wire [79:0] areas;wire [191:0] boxes;
color_multitarget #(.H_ACTIVE(W),.V_ACTIVE(H)) dut(.clk(clk),.rst_n(rst),.rgb(rgb),.timing(t),
 .valid(valid),.overflow(overflow),.target_count(count),.colors(colors),.shapes(shapes),.areas(areas),.boxes(boxes));
`ifdef COLOR_HD
`include "D:/codex_project/FPGA_competiton/src/sim/fixtures/color_shapes_hd/expected.vh"
`else
`ifdef COLOR_NOISE
`include "D:/codex_project/FPGA_competiton/src/sim/fixtures/color_shapes_noise/expected.vh"
`else
`include "D:/codex_project/FPGA_competiton/src/sim/fixtures/color_shapes/expected.vh"
`endif
`endif
reg [23:0] image[0:W*H-1];reg test_done=0;integer errors=0,checks=0,f,x,y,s,k,expected_count;
reg [25:0] expected;
initial begin
 repeat(5)@(negedge clk);rst=1;
 for(f=0;f<CASES;f=f+1)begin
  $readmemh(fixture_name(f),image);
  for(y=0;y<H;y=y+1)begin
   for(x=0;x<W;x=x+1)begin @(negedge clk);rgb=image[y*W+x];t={2'b00,1'b1,(x==0 && y==0),(x==W-1)};end
   @(negedge clk);t=0;rgb=0;repeat(3)@(negedge clk);
  end
  @(negedge clk);t=0;rgb=0;k=0;
  while(dut.state!=0 && k<3*W*H+10)begin @(negedge clk);k=k+1;end
  repeat(3)@(negedge clk);checks=checks+1;expected_count=0;
  if(!valid || overflow || k>=3*W*H+10)begin errors=errors+1;$display("FAIL complete case%0d valid%0d overflow%0d state%0d clocks%0d",f,valid,overflow,dut.state,k);end
  for(s=0;s<4;s=s+1)begin
   expected=expected_color_shape(f,s);if(expected[25:23]!=0)expected_count=expected_count+1;
   if(colors[s*3+:3]!==expected[25:23] || shapes[s*3+:3]!==expected[22:20] || areas[s*20+:20]!==expected[19:0] || boxes[s*48+:48]!==expected_box(f,s))begin
    errors=errors+1;$display("FAIL case%0d slot%0d color%0d/%0d shape%0d/%0d area%0d/%0d bbox%h/%h polygon_n%0d",f,s,colors[s*3+:3],expected[25:23],shapes[s*3+:3],expected[22:20],areas[s*20+:20],expected[19:0],boxes[s*48+:48],expected_box(f,s),dut.polygon.count);
   end
  end
  if(count!==expected_total(f))begin errors=errors+1;$display("FAIL case%0d count%0d/%0d",f,count,expected_total(f));end
  $display("CASE %0d done clocks%0d count%0d errors%0d",f,k,count,errors);
 end
 test_done=1;if(errors==0)$display("PASS color_multitarget cases%0d checks%0d",CASES,checks);else $display("FAIL color_multitarget errors%0d",errors);$finish;
end
endmodule
