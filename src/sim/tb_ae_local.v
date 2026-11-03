`timescale 1ns/1ps
module tb_ae_local;
 localparam W=100,H=90;
 reg clk=0,rst=0,de=0,user=0,cfg=1,hold=0;reg [23:0] rgb=0;
 always #5 clk=~clk;
 wire [27:0] sum;wire [19:0] count,clip;wire toggle,valid;wire [1:0] local_high;
 wire [10:0] ae;wire [7:0] ag;wire req;
 ae_stats #(.H_ACTIVE(W),.V_ACTIVE(H)) stats(.clk(clk),.rst_n(rst),.de(de),.user(user),.rgb(rgb),.stats_sum(sum),.stats_n(count),.stats_clipped(clip),.stats_toggle(toggle),.stats_valid(valid),.stats_local_high(local_high));
 ae_ctrl #(.RATE_DIV(1)) ctrl(.clk(clk),.rst_n(rst),.cfg_done(cfg),.manual_evt(1'b0),.manual_toggle(1'b0),.stats_sum(sum),.stats_clipped(clip),.stats_local_high(local_high),.stats_toggle(toggle),.hold_control(hold),.cur_ae(ae),.cur_ag(ag),.auto_ae(ae),.auto_ag(ag),.auto_valid(),.auto_req(req),.frame_cnt(),.silent_cnt());
 integer checks=0,errors=0,oldae,oldag;reg test_done=0;
 task check;input [400:0] t;input ok;begin checks=checks+1;if(ok!==1'b1)begin errors=errors+1;$display("FAIL %0s ae%0d local%0d count%0d",t,ae,local_high,count);end end endtask
 task frame;input integer highs,pick,size;integer x,y,n,t;begin
 n=0;
 for(y=0;y<H;y=y+1)for(x=0;x<W;x=x+1)if(y*W+x<size)begin
 @(negedge clk);de=1;user=x==0 && y==0;t=(y<30?0:y<60?1:2)*3+(x<33?0:x<66?1:2);rgb=24'h141414;
 if(t==pick && n<highs)begin rgb=24'h14f014;n=n+1;end
 end
 @(negedge clk);de=0;user=0;repeat(16)@(negedge clk);
 end endtask
 initial begin
 repeat(4)@(negedge clk);rst=1;
 frame(31,0,W*H);frame(32,8,W*H);check("uneven first tile enter equality and first pixel",valid==0 && local_high==2 && clip==0 && count==W*H);
 oldae=ae;frame(16,8,W*H);check("last tile enter equality overrides dark mean",local_high==2 && ae<oldae);
 oldae=ae;frame(15,8,W*H);check("local stay band keeps decreasing",local_high==1 && ae<oldae);
 oldae=ae;frame(0,0,W*H);check("last tile below exit threshold clears",local_high==0 && ae>oldae);
 frame(0,0,W*H);oldae=ae;frame(32,8,W*H-1);frame(0,0,W*H);
 check("malformed high frame publishes no local danger",local_high==0 && ae>=oldae);
 frame(40,4,W*H);cfg=0;oldae=ae;frame(40,4,W*H);frame(40,4,W*H);
 check("busy outputs stay immutable while local protection works",ae==oldae);
 cfg=1;repeat(16)@(negedge clk);check("busy completion publishes pending decrease",ae<oldae);
 hold=1;repeat(16)@(negedge clk);oldae=ae;oldag=ag;frame(40,4,W*H);frame(40,4,W*H);
 check("lock suppresses local control writes",ae==oldae && ag==oldag && !req);
 hold=0;repeat(16)@(negedge clk);frame(40,4,W*H);check("unlock resumes bounded local protection",ae<oldae);
 test_done=1;if(errors==0)$display("PASS ae_local checks%0d raw_preCCM tile_threshold uneven_tiles first_pixel hysteresis dark_override badframe busy hold recover",checks);else $display("FAIL ae_local errors%0d",errors);$finish;
 end
endmodule
