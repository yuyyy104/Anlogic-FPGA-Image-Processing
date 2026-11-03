`timescale 1ns/1ps
module tb_shape_labels;
reg clk=0,rst=0,rv=0,re=0,fe=0,ro=0;always #5 clk=~clk;
reg [8:0] x0=0,x1=0;reg [7:0] y=0;wire ack,done,valid,overflow;wire [7:0] count;
wire [15:0] area0,area1;wire [8:0] sx0,sx1,xl0,xh0,xl1,xh1;wire [7:0] sy0,sy1,yl0,yh0,yl1,yh1;
integer errors=0,checks=0,row,k;reg test_done=0;
shape_labels dut(.clk(clk),.rst_n(rst),.run_valid(rv),.run_x0(x0),.run_x1(x1),.run_y(y),.run_row_end(re),.run_ack(ack),
 .runs_overflow(ro),.scan_overflow(1'b0),.frame_end(fe),.frame_invalid(1'b0),.frame_global_change(1'b0),.global_change(),
 .result_done(done),.regions_valid(valid),.region_count(count),.regions_overflow(overflow),
 .r0_area(area0),.r1_area(area1),.r0_seed_x(sx0),.r1_seed_x(sx1),.r0_seed_y(sy0),.r1_seed_y(sy1),
 .r0_xmin(xl0),.r0_xmax(xh0),.r0_ymin(yl0),.r0_ymax(yh0),.r1_xmin(xl1),.r1_xmax(xh1),.r1_ymin(yl1),.r1_ymax(yh1));
task run;input integer lo,hi;begin
 x0=lo;x1=hi;rv=1;k=0;while(!ack && k<10000)begin @(negedge clk);k=k+1;end
 rv=0;@(negedge clk);if(k==10000)begin errors=errors+1;$display("FAIL label ack");end
end endtask
task finish;begin
 fe=1;@(negedge clk);fe=0;k=0;while(!done && k<10000)begin @(negedge clk);k=k+1;end
 checks=checks+1;if(!done)begin errors=errors+1;$display("FAIL label done");end
end endtask
initial begin
 repeat(5)@(negedge clk);rst=1;
 for(row=0;row<36;row=row+1)begin
  y=row;
  if(row==10 || row==12)begin run(10,20);run(40,50);end
  if(row==11)run(10,50);
  if(row>=30 && row<=32)run(100+3*(row-30),102+3*(row-30));
  re=1;@(negedge clk);re=0;repeat(500)@(negedge clk);
 end
 finish;
 if(!valid || overflow || count!=2 || area0!=85 || area1!=9 || {sx0,sy0,xl0,xh0,yl0,yh0}!=={9'd10,8'd10,9'd10,9'd50,8'd10,8'd12} ||
 {sx1,sy1,xl1,xh1,yl1,yh1}!=={9'd100,8'd30,9'd100,9'd108,8'd30,8'd32})begin errors=errors+1;$display("FAIL CCL merge/fork diagonal8 count%0d area%0d/%0d seed%0d,%0d",count,area0,area1,sx0,sy0);end
 rst=0;repeat(3)@(negedge clk);rst=1;ro=1;@(negedge clk);ro=0;finish;
 if(valid || !overflow || count!=0 || area0!=0)begin errors=errors+1;$display("FAIL CCL overflow clear");end
 test_done=1;if(errors==0)$display("PASS shape_labels checks%0d merging_fork earliest_seed diagonal8 retire_reuse overflow_clear",checks);else $display("FAIL shape_labels errors%0d",errors);$finish;
end
endmodule
