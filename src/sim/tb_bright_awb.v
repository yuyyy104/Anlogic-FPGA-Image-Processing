`timescale 1ns/1ps
module tb_bright_awb;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,valid=0,user=0,last=0,freeze=0;reg [95:0] data=0;
 wire [40:0] status;wire strobe;integer checks=0,errors=0;reg test_done=0;
 frame_awb #(.IMG_WIDTH(128),.IMG_HEIGHT(64),.MIN_SAMPLES(16),
 .REF_R_Q8({{4{10'd256}},10'd210}),.REF_B_Q8({{4{10'd256}},10'd234})) dut(
 .I_clk(clk),.I_rst_n(rst),.I_tvalid(valid),.I_tuser(user),.I_tlast(last),.I_tdata(data),.I_freeze(freeze),
 .I_tready(),.O_tvalid(),.O_tuser(),.O_tlast(),.O_tdata(),.O_tready(1'b1),.O_frozen(),.O_status(status),.O_status_valid(strobe));
 function integer roi;input integer x,y;begin roi=7;
 if(x>=56 && x<72 && y>=28 && y<36)roi=0;
 else if(x>=8 && x<24 && y>=4 && y<12)roi=1;
 else if(x>=104 && x<120 && y>=4 && y<12)roi=2;
 else if(x>=8 && x<24 && y>=52 && y<60)roi=3;
 else if(x>=104 && x<120 && y>=52 && y<60)roi=4;end endfunction
 reg [23:0] colors[0:4];integer i,f,oldr,oldb;
 task check;input [450:0] tag;input ok;begin checks=checks+1;if(ok!==1'b1)begin errors=errors+1;$display("FAIL %0s",tag);end end endtask
 task reset;begin @(negedge clk);rst=0;valid=0;user=0;freeze=0;repeat(4)@(negedge clk);rst=1;end endtask
 task dark;begin for(i=0;i<5;i=i+1)colors[i]=24'h141414;end endtask
 task frame;input integer malformed,texture;integer x,y,p;reg [23:0] v;begin
 for(y=0;y<64;y=y+1)begin
 for(x=0;x<(malformed?31:32);x=x+1)begin
 @(negedge clk);valid=1;user=x==0 && y==0;last=x==(malformed?30:31);p=roi(x*4+3,y);v=p<5?colors[p]:24'h141414;
 if(texture && p==0 && y[0])v=24'h90b090;data={4{v}};
 end
 @(negedge clk);valid=0;user=0;last=0;
 end
 repeat(900)@(negedge clk);
 end endtask
 initial begin
 reset();dark();colors[0]=24'hacf1b0;
 frame(0,0);frame(0,0);check("first usable observation waits",!dut.pending && dut.single_streak==1);
 frame(0,0);check("second observation waits",!dut.pending && dut.single_streak==2);
 frame(0,0);check("third stable single bright ROI accepted",dut.pending && dut.pending_r==294 && dut.pending_b==320 && dut.status_reason==1);
 repeat(20)frame(0,0);check("single bright white recovers R and B",dut.gain_r>=292 && dut.gain_r<=296 && dut.gain_b>=318 && dut.gain_b<=322);
 check("single cannot move trusted multi-region anchor",dut.trusted_r==256 && dut.trusted_b==256);
 check("status actual gains and sample cohort",status[40:31]==dut.gain_r && status[30:21]==dut.gain_b && status[20:10]==32 && status[9:7]==0 && status[6:4]==1 && status[3:0]==1);
 oldr=dut.gain_r;oldb=dut.gain_b;freeze=1;repeat(4)frame(0,0);
 check("freeze resets confidence and holds",dut.single_streak==0 && !dut.pending && dut.gain_r==oldr && dut.gain_b==oldb && status[3:0]==6);
 freeze=0;frame(0,0);frame(0,0);check("unfreeze rebuilds single confidence",dut.single_streak<=1 && !dut.pending);
 frame(1,0);frame(0,0);check("bad frame breaks temporal streak",dut.single_streak==0 && !dut.pending && dut.status_reason==5);
 reset();dark();colors[0]=24'h80c880;repeat(8)frame(0,0);
 check("static green does not slowly drift trusted anchor",dut.gain_r==256 && dut.gain_b==256 && !dut.pending);
 reset();dark();colors[0]=24'h90d28a;repeat(8)frame(0,0);
 check("single ratio beyond absolute trusted bound holds",dut.gain_b==256 && dut.trusted_b==256 && !dut.pending);
 reset();dark();colors[0]=24'hacf1b0;colors[1]=24'hf0c8c8;repeat(8)frame(0,0);
 check("two conflicting bright candidates do not become single fallback",!dut.pending && dut.single_streak==0 && dut.gain_r==256 && dut.gain_b==256);
 reset();dark();colors[0]=24'hacf1b0;repeat(6)frame(0,1);
 check("textured singleton rejects nonuniform patch",!dut.pending && dut.single_streak==0);
 reset();dark();colors[0]=24'hacf1b0;frame(0,0);frame(0,0);
 colors[0]=24'h141414;colors[1]=24'hc8f0c8;frame(0,0);frame(0,0);
 check("moving patch restarts confidence",!dut.pending && dut.single_streak==1 && dut.single_patch==1);
 reset();for(i=0;i<5;i=i+1)colors[i]=24'hc8c8c8;colors[0]=24'ha4c8b7;repeat(4)frame(0,0);
 check("multi consensus remains first choice",dut.best_votes==5 && dut.pending && !dut.pending_single && dut.status_reason==0);
 test_done=1;if(errors==0)$display("PASS bright_awb checks%0d sustained_single calibrated_refs no_dark_vote bounded_anchor green conflicting textured moving freeze malformed status",checks);else $display("FAIL bright_awb errors%0d",errors);$finish;
 end
endmodule
