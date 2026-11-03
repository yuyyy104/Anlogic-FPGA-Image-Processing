`timescale 1ns/1ps
module tb_frame_awb;
 reg clk=0;always #5 clk=~clk;
 reg rst=0,valid=0,user=0,last=0,freeze=0;reg [95:0] data=0;
 wire ov,ou,ol,frozen;wire [95:0] od;
 integer errors=0,checks=0;reg test_done=0;
 frame_awb #(.IMG_WIDTH(16),.IMG_HEIGHT(8),.MIN_SAMPLES(2),.REF_R_Q8({5{10'd256}}),.REF_B_Q8({5{10'd256}})) dut(
  .I_clk(clk),.I_rst_n(rst),.I_tvalid(valid),.I_tuser(user),.I_tlast(last),.I_tdata(data),.I_freeze(freeze),
  .I_tready(),.O_tvalid(ov),.O_tuser(ou),.O_tlast(ol),.O_tdata(od),.O_tready(1'b1),.O_frozen(frozen));
 reg pv=0,pu=0,pl=0;reg [95:0] pd=0,wanted;integer l,rr,bb;
 always @(posedge clk)begin
  if(rst)begin
   wanted=0;
   for(l=0;l<4;l=l+1)begin
    rr=(data[l*24+16+:8]*dut.use_r+128)/256;bb=(data[l*24+:8]*dut.use_b+128)/256;
    wanted[l*24+:24]={(rr>255?8'd255:rr[7:0]),data[l*24+8+:8],(bb>255?8'd255:bb[7:0])};
   end
   #1;checks=checks+1;
   if(ov!==pv || ou!==pu || ol!==pl || (pv && od!==pd))begin errors=errors+1;if(errors<8)$display("FAIL lane/timing");end
   pv=valid;pu=user;pl=last;pd=wanted;
  end else begin pv=0;pu=0;pl=0;pd=0;end
 end
 task check;input [350:0] tag;input ok;begin checks=checks+1;if(!ok)begin errors=errors+1;$display("FAIL %s",tag);end end endtask
 task reset;begin @(negedge clk);rst=0;valid=0;user=0;last=0;freeze=0;repeat(4)@(negedge clk);rst=1;end endtask
 function integer roi;input integer x,y;
  begin roi=-1;
   if(x>=6 && x<10 && y>=3 && y<5)roi=0;
   else if(x<4 && y<2)roi=1;
   else if(x>=12 && y<2)roi=2;
   else if(x<4 && y>=6)roi=3;
   else if(x>=12 && y>=6)roi=4;
  end
 endfunction
 reg [23:0] colors[0:4];
 task frame;input integer early,width,tail;integer x,y,p;
  begin
   if(early)begin @(negedge clk);valid=0;user=1;last=0;@(negedge clk);user=0;repeat(4)@(negedge clk);end
   for(y=0;y<8;y=y+1)begin
    for(x=0;x<width;x=x+1)begin
     @(negedge clk);valid=1;user=!early && y==0 && x==0;last=x==width-1;
     p=roi(x*4+3,y);data={24'hfdfcfa,24'h010203,24'hff2010,p<0?24'hff2020:colors[p]};
    end
    if(y<7 || !tail)begin @(negedge clk);valid=0;user=0;last=0;end
   end
   if(!tail)repeat(750)@(negedge clk);
  end
 endtask
 task close_frame;input integer concurrent;
  begin @(negedge clk);valid=concurrent;user=1;last=0;data={4{24'h646464}};
   @(negedge clk);user=0;valid=0;repeat(750)@(negedge clk);
  end
 endtask
 task set_all;input [23:0] p;integer j;begin for(j=0;j<5;j=j+1)colors[j]=p;end endtask
 integer j,n,gr,gb;
 initial begin
  reset();set_all(24'h506478);frame(1,4,0);
  for(j=0;j<5;j=j+1)check("two eligible samples in every patch",dut.counts[j]==2 && dut.sums_r[j]==160 && dut.sums_g[j]==200 && dut.sums_b[j]==240);
  close_frame(0);check("independent exact 320/213 division",dut.pending && dut.pending_r==320 && dut.pending_b==213 && dut.best_votes==5);
  repeat(22)frame(1,4,0);check("neutral source converges while red occupies frame",dut.gain_r==320 && dut.gain_b>=211 && dut.gain_b<=215);
  gr=dut.gain_r;gb=dut.gain_b;freeze=1;repeat(5)frame(1,4,0);check("freeze holds coherent gains",frozen && dut.gain_r==gr && dut.gain_b==gb && !dut.pending);
  freeze=0;repeat(4)@(negedge clk);frame(1,4,0);check("unfreeze drops frozen observation",!frozen && dut.gain_r==gr && dut.gain_b==gb);
  reset();set_all(24'h506478);colors[0]=24'ha09060;frame(1,4,0);close_frame(0);
  check("wood patch cannot override four agreeing white patches",dut.pending && dut.pending_r==320 && dut.pending_b==213 && dut.best_votes==4);
  reset();set_all(24'hff2020);colors[2]=24'h506478;frame(1,4,0);close_frame(0);
  check("one white patch is insufficient",!dut.pending && dut.gain_r==256 && dut.gain_b==256);
  colors[4]=24'h506478;frame(1,4,0);close_frame(0);check("two independent patches form confidence minimum",dut.pending && dut.pending_r==320 && dut.pending_b==213 && dut.best_votes==2);
  reset();set_all(24'hff2020);colors[1]=24'h78a078;colors[2]=24'h78a078;frame(1,4,0);close_frame(0);check("low coverage common cast rejected",!dut.pending && dut.best_votes==2);
  reset();set_all(24'hff2020);colors[1]=24'h81a081;colors[2]=24'h789f79;frame(1,4,0);close_frame(0);check("fusion cannot cross common cast gate with only two references",!dut.pending && dut.pending_r==328 && dut.pending_b==326);
  reset();set_all(24'h608060);frame(1,4,0);close_frame(0);check("high coverage white startup can recover unknown old gains",dut.pending && dut.pending_r==341 && dut.pending_b==341 && dut.best_votes==5);
  reset();set_all(24'hff2020);colors[1]=24'h608060;colors[2]=24'h608060;colors[3]=24'h608060;frame(1,4,0);close_frame(0);check("three spatially separate startup references restore common cast",dut.pending && dut.pending_r==341 && dut.pending_b==341 && dut.best_votes==3);
  reset();set_all(24'hf040f0);frame(1,4,0);close_frame(0);check("saturated magenta rejected",!dut.pending);
  reset();set_all(24'h080808);frame(1,4,0);close_frame(0);check("dark no reference retains gains",!dut.pending);
  reset();set_all(24'hffffff);frame(1,4,0);close_frame(0);check("clipped no reference retains gains",!dut.pending);
  reset();set_all(24'ha09060);frame(1,4,0);close_frame(0);check("warm illuminant opposing gains remains admissible",dut.pending_r==230 && dut.pending_b==384 && dut.pending);
  reset();set_all(24'h6090a0);frame(1,4,0);close_frame(0);check("cool illuminant opposing gains remains admissible",dut.pending_r==384 && dut.pending_b==230 && dut.pending);
  reset();set_all(24'h50a078);frame(1,4,0);close_frame(0);check("gain upper equality retained without numerator overflow",dut.pending_r==512 && dut.pending_b==341 && dut.pending);
  reset();set_all(24'h80a090);frame(1,4,0);close_frame(0);check("mild green neutral ratio remains admissible",dut.pending_r==320 && dut.pending_b==284 && dut.pending);
  // Exact frame closure when the old last word abuts the new marker.
  for(n=0;n<4;n=n+1)begin reset();set_all(24'h506478);frame(n/2,4,1);close_frame(n%2);
   check("tail/concurrent/early marker closes old complete frame",dut.pending && dut.pending_r==320 && dut.pending_b==213);
  end
  reset();set_all(24'h506478);frame(1,3,0);close_frame(0);check("short lines cannot calibrate",!dut.pending);
  reset();set_all(24'h506478);frame(1,4,0);
  @(negedge clk);user=1;@(negedge clk);user=0;
  repeat(30)@(negedge clk);check("divider active",dut.state!=0);
  freeze=1;repeat(4)@(negedge clk);user=1;@(negedge clk);user=0;repeat(750)@(negedge clk);
  check("freeze cancels active divider and cannot publish later",frozen && !dut.pending && dut.state==0 && dut.gain_r==256 && dut.gain_b==256);
  test_done=1;if(errors==0)$display("PASS frame_awb checks%0d errors0 five_reference consensus wood_outlier single_patch warm_cold cast_bad dark_clip freeze bad_tail four_lanes timing2",checks);else $display("FAIL frame_awb errors%0d",errors);$finish;
 end
endmodule
