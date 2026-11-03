`timescale 1ns/1ps
module tb_nine_regions;
 localparam W=512,H=256;
 reg clk=0,rst=0,en=1;reg [4:0] timing=0;reg [23:0] pin=0,pout=0;
 always #5 clk=~clk;
 wire [215:0] mi,mo;wire [116:0] ci,co;wire valid;
 color_regions #(.H_ACTIVE(W),.V_ACTIVE(H),.POINTS(9)) dut(.clk(clk),.rst_n(rst),.enable(en),.timing(timing),.rgb_in(pin),.rgb_out(pout),.mean_in(mi),.mean_out(mo),.clip_in(ci),.clip_out(co),.valid(valid));
 integer errors=0,checks=0,g,f;reg test_done=0;reg [215:0] old;
 task check;input [300:0] t;input ok;begin checks=checks+1;if(ok!==1'b1)begin errors=errors+1;$display("FAIL %0s",t);end end endtask
 task frame;input integer size;integer n;begin for(n=0;n<size;n=n+1)begin @(negedge clk);timing={2'b0,1'b1,n==0,n%W==W-1};pin=24'hffffff;pout=24'hffffff;end @(negedge clk);timing=0;end endtask
 task publish;begin @(negedge clk);timing=5'b00110;@(negedge clk);timing=0;end endtask
 initial begin
 repeat(4)@(negedge clk);rst=1;
 for(f=0;f<4;f=f+1)frame(W*H);publish();check("four-frame nine-point publication",valid);
 for(g=0;g<9;g=g+1)begin
 check("all 18 RGB banks max sums preserved",mi[g*24+:24]==24'hffffff && mo[g*24+:24]==24'hffffff);
 check("all 18 clipped counts exact 4096",ci[g*13+:13]==4096 && co[g*13+:13]==4096);
 end
 old=mi;frame(W*H-1);publish();check("short frame invalidates all nine coherently",!valid && mi==old);
 for(f=0;f<4;f=f+1)frame(W*H);publish();check("four valid frames recover",valid);
 en=0;publish();check("SW4 off drops validity",!valid);
 test_done=1;if(errors==0)$display("PASS nine_regions checks%0d 18banks maximum_255 four_frames clip4096 incomplete coherent SW4",checks);else $display("FAIL nine_regions errors%0d",errors);$finish;
 end
endmodule
