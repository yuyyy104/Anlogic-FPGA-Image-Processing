`timescale 1ns/1ps
module tb_awb_calibrated_refs;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,valid=0,user=0,last=0;reg [95:0] data=0;
 wire [40:0] status;wire strobe;integer errors=0,checks=0;reg test_done=0;
 frame_awb #(.IMG_WIDTH(128),.IMG_HEIGHT(64),.MIN_SAMPLES(16)) dut(
 .I_clk(clk),.I_rst_n(rst),.I_tvalid(valid),.I_tuser(user),.I_tlast(last),.I_tdata(data),.I_freeze(1'b0),
 .I_tready(),.O_tvalid(),.O_tuser(),.O_tlast(),.O_tdata(),.O_tready(1'b1),.O_frozen(),.O_status(status),.O_status_valid(strobe));
 function integer roi;input integer x,y;begin roi=7;
 if(x>=56 && x<72 && y>=28 && y<36)roi=0;
 else if(x>=8 && x<24 && y>=4 && y<12)roi=1;
 else if(x>=104 && x<120 && y>=4 && y<12)roi=2;
 else if(x>=8 && x<24 && y>=52 && y<60)roi=3;
 else if(x>=104 && x<120 && y>=52 && y<60)roi=4;end endfunction
 // White-patch ratios from the fitted physical mesh, independent of DUT params.
 integer ref_r[0:4],ref_b[0:4];reg [23:0] colors[0:4];integer f,x,y,p,r,b,i;
 task check;input [255:0] tag;input ok;begin checks=checks+1;if(ok!==1'b1)begin errors=errors+1;$display("FAIL %0s",tag);end end endtask
 initial begin
 ref_r[0]=211;ref_r[1]=282;ref_r[2]=273;ref_r[3]=265;ref_r[4]=254;
 ref_b[0]=234;ref_b[1]=268;ref_b[2]=266;ref_b[3]=263;ref_b[4]=254;
 for(i=0;i<5;i=i+1)begin r=(180*ref_r[i]+157)/314;b=(180*ref_b[i]+169)/339;colors[i]={r[7:0],8'd180,b[7:0]};end
 repeat(4)@(negedge clk);rst=1;
 for(f=0;f<36;f=f+1)begin
 for(y=0;y<64;y=y+1)begin
 for(x=0;x<32;x=x+1)begin
 @(negedge clk);valid=1;user=x==0 && y==0;last=x==31;p=roi(x*4+3,y);data={4{p<5?colors[p]:24'h141414}};
 end
 @(negedge clk);valid=0;user=0;last=0;
 end
 repeat(900)@(negedge clk);
 end
 check("calibrated multi-patch consensus",dut.best_votes==5 && dut.status_reason==0);
 check("default calibrated gains converge",dut.gain_r>=310 && dut.gain_r<=318 && dut.gain_b>=335 && dut.gain_b<=343);
 check("status reports actual gains",status[40:31]==dut.gain_r && status[30:21]==dut.gain_b);
 test_done=1;if(errors==0)$display("PASS awb_calibrated_refs checks%0d default_profile five_white_ROIs gain%0d/%0d",checks,dut.gain_r,dut.gain_b);else $display("FAIL awb_calibrated_refs errors%0d",errors);$finish;
 end
endmodule
