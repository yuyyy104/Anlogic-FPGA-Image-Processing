`timescale 1ns/1ps
module tb_color_multi_fault;
localparam W=512,H=256;
reg clk=0,rst=0;always #5 clk=~clk;
reg [23:0] rgb=0;reg [4:0] t=0;
wire valid,overflow;wire [7:0] count;wire [11:0] colors,shapes;wire [79:0] areas;wire [191:0] boxes;
color_multitarget #(.H_ACTIVE(W),.V_ACTIVE(H)) dut(.clk(clk),.rst_n(rst),.rgb(rgb),.timing(t),
 .valid(valid),.overflow(overflow),.target_count(count),.colors(colors),.shapes(shapes),.areas(areas),.boxes(boxes));
reg [23:0] image[0:W*H-1];integer errors=0,checks=0,k,x,y,f,kind;reg test_done=0,saw_four=0;
function [23:0] paint;input integer a,b,c;integer id;begin
 paint=24'h606060;
 if(c==0)paint=image[b*W+a];
 if(c==2 && ((a/4)%2)==0 && b>=16 && b<200)paint=24'hdc2d23;
 if(c==3 && ((a/4)%4)<3 && ((b/4)%4)<3)begin
  id=((b/16)%4)+1;
  case(id)1:paint=24'hdc2d23;2:paint=24'h23d22d;3:paint=24'h1e2ddc;4:paint=24'hd7d21e;endcase
 end
end endfunction
task reset;begin rst=0;t=0;repeat(4)@(negedge clk);rst=1;end endtask
task frame;input integer c;input integer malformed;begin
 for(y=0;y<H;y=y+1)for(x=0;x<W;x=x+1)begin
  @(negedge clk);rgb=paint(x,y,c);t={2'b00,1'b1,(x==0 && y==0),(x==W-1)};
  if(malformed && y==2 && x==20)t[0]=1;
 end
end endtask
task settle;begin
 @(negedge clk);t=0;k=0;while(dut.state!=0 && k<3*W*H+10)begin @(negedge clk);k=k+1;end
 repeat(3)@(negedge clk);checks=checks+1;
 if(k>=3*W*H+10)begin errors=errors+1;$display("FAIL fault settle");end
end endtask
task zero_invalid;begin checks=checks+1;
 if(valid!==0 || overflow!==1 || {count,colors,shapes,areas,boxes}!==0)begin errors=errors+1;$display("FAIL fault invalid clear count%0d v%0d o%0d",count,valid,overflow);end
end endtask
always @(negedge clk)if(rst && valid && count==4)begin
 saw_four=1;
 if(colors!==12'h70a || shapes!==12'h70a)begin errors=errors+1;if(errors<5)$display("FAIL protected bank result %h/%h",colors,shapes);end
end
always @(posedge clk)if(rst)begin
 if(dut.complete)$display("CAPTURE time%0t state%0d cap%0d scan%0d",$time,dut.state,dut.cap_bank,dut.scan_bank);
 if(dut.state==50)$display("PUBLISH time%0t count%0d bad%0d",$time,dut.total_count,dut.bad);
end
initial begin
 $readmemh("D:/codex_project/FPGA_competiton/src/sim/fixtures/color_shapes/four_colours.mem",image);
 reset;frame(0,0);settle;
 if(!valid || count!=4)begin errors=errors+1;$display("FAIL initial four");end
 frame(1,1);settle;zero_invalid;
 frame(1,0);settle;if(!valid || overflow || count!=0)begin errors=errors+1;$display("FAIL recovery empty");end
 frame(0,0);settle;
 // A short frame followed by a new marker cancels the old published cohort.
 @(negedge clk);t=5'b00110;rgb=24'hdc2d23;repeat(25)@(negedge clk);
 @(negedge clk);t=5'b00110;@(negedge clk);t=0;repeat(2)@(negedge clk);zero_invalid;
 reset;frame(2,0);settle;zero_invalid;
 reset;frame(3,0);settle;zero_invalid;
 // No blanking between complete frames: protect the processing bank and
 // accept the latest complete capture when idle, without video backpressure.
 reset;saw_four=0;frame(0,0);for(f=0;f<6;f=f+1)frame(1,0);settle;
 checks=checks+1;if(!saw_four || !valid || count!=0 || overflow)begin errors=errors+1;$display("FAIL continuous four->empty saw%0d count%0d",saw_four,count);end
 reset;frame(0,0);@(negedge clk);t=0;
 force dut.label_done=0;
 repeat(3*W*H+10)@(negedge clk);release dut.label_done;zero_invalid;
 frame(1,0);settle;if(!valid || overflow || count!=0)begin errors=errors+1;$display("FAIL watchdog recovery");end
 test_done=1;if(errors==0)$display("PASS color_multi_fault checks%0d malformed shortframe run_capacity total_capacity zero_blank busy_bank watchdog recovery",checks);else $display("FAIL color_multi_fault errors%0d",errors);$finish;
end
endmodule
