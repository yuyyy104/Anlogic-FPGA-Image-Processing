`timescale 1ns/1ps
module tb_awb_status_cdc;
 reg sc=0,dc=0,rst=0,run_dst=1,sv=0;reg [40:0] sd=0;wire [40:0] dd;
 always #5 sc=~sc;always #7 if(run_dst)dc=~dc;
 awb_status_cdc dut(.src_clk(sc),.dst_clk(dc),.rst_n(rst),.src_valid(sv),.src_data(sd),.dst_data(dd));
 integer errors=0,checks=0;reg test_done=0;reg [40:0] packet=41'h123456789ab;
 task check;input [350:0] t;input ok;begin checks=checks+1;if(ok!==1'b1)begin errors=errors+1;$display("FAIL %0s",t);end end endtask
 task send;input [40:0] p;begin @(negedge sc);sd=p;sv=1;@(negedge sc);sv=0;end endtask
 initial begin
 repeat(4)@(negedge sc);rst=1;send(packet);repeat(15)@(negedge sc);
 check("async packet arrives atomically",dd==packet && dut.ack_2==dut.req);
 @(negedge dc);run_dst=0;packet=41'h1abcdef0123;send(packet);send(41'h111);send(41'h222);repeat(10)@(negedge sc);
 check("producer holds immutable packet while destination paused",dut.held==packet && dd!=packet);
 run_dst=1;repeat(20)@(negedge sc);check("paused destination captures original cohort",dd==packet);
 packet=41'h155aa55aa55;send(packet);repeat(15)@(negedge sc);check("following publication recovers",dd==packet);
 @(negedge sc);rst=0;repeat(4)@(negedge sc);check("reset clears both epochs",dd==0 && dut.req==0 && dut.ack==0);
 rst=1;packet={10'd512,10'd128,11'd1024,3'd4,3'd5,4'd7};send(packet);repeat(20)@(negedge sc);check("all diagnostic fields survive reset",dd==packet);
 test_done=1;if(errors==0)$display("PASS awb_status_cdc checks%0d async pause busy_drop held_cohort reset next_frame",checks);else $display("FAIL awb_status_cdc errors%0d",errors);$finish;
 end
endmodule
