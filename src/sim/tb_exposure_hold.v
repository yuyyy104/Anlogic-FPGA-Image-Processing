`timescale 1ns/1ps
module tb_exposure_hold;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,hold=0,cfg=1,toggle=0;
    reg [27:0] sum=28800<<12;reg [19:0] clip=0;
    wire [10:0] ae;wire [7:0] ag;wire req,av;
    integer errors=0,checks=0;reg test_done=0;
    ae_ctrl #(.REARM_FRAMES(8),.CLIP_ENTER(100),.CLIP_EXIT(50)) dut(.clk(clk),.rst_n(rst),.hold_control(hold),.stats_sum(sum),.stats_clipped(clip),.stats_toggle(toggle),.cfg_done(cfg),.manual_evt(1'b0),.manual_toggle(1'b0),.cur_ae(ae),.cur_ag(ag),.auto_valid(av),.auto_ae(ae),.auto_ag(ag),.auto_req(req),.frame_cnt(),.silent_cnt());
    task frames;input integer n;integer i;begin for(i=0;i<n;i=i+1)begin @(negedge clk);toggle=~toggle;repeat(10)@(negedge clk);end end endtask
    task check;input [255:0] name;input ok;begin checks=checks+1;if(!ok)begin errors=errors+1;$display("FAIL %s",name);end end endtask
    integer oldae,oldag;
    initial begin
        repeat(5)@(negedge clk);rst=1;frames(4);oldae=ae;
        sum=10000<<12;clip=100;frames(4);
        check("highlight overrides dark mean",ae<oldae);oldae=ae;
        clip=75;frames(4);check("highlight hysteresis continues",ae<oldae);
        clip=50;frames(8);oldae=ae;oldag=ag;frames(4);check("dark recovers after highlight clears",ae>oldae || ag>oldag);
        hold=1;repeat(12)@(negedge clk);oldae=ae;oldag=ag;
        sum=40000<<12;clip=900;frames(320);
        check("hold never rearms or requests",ae==oldae && ag==oldag && !req);
        hold=0;repeat(12)@(negedge clk);frames(4);check("unlock resumes auto",ae<oldae || ag<oldag);
        cfg=0;hold=1;oldae=ae;frames(8);check("busy publication remains immutable",ae==oldae && !req);
        cfg=1;repeat(12)@(negedge clk);check("locked after busy completion",ae==oldae && !req);
        test_done=1;if(errors==0)$display("PASS exposure_hold checks=%0d errors=0",checks);else $display("FAIL exposure_hold errors=%0d",errors);$finish;
    end
endmodule
