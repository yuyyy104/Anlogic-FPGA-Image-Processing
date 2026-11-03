`timescale 1ns/1ps
module tb_ae_ctrl;
    reg clk=0, rst_n=0, cfg_done=1, manual_evt=0, manual_toggle=0;
    reg [27:0] stats_sum=0;
    reg stats_toggle=0;
    reg [10:0] cur_ae=100;
    reg [7:0] cur_ag=16;
    wire auto_valid, auto_req;
    wire [10:0] auto_ae;
    wire [7:0] auto_ag;
    wire [15:0] frame_cnt, silent_cnt;
    wire top_auto_valid, top_auto_req;
    wire [10:0] top_auto_ae;
    wire [7:0] top_auto_ag;
    integer checks=0, errors=0, test_done=0, i;
    integer ae_before, ag_before;
    always #5 clk=~clk;
    ae_ctrl dut(.clk(clk),.rst_n(rst_n),.cfg_done(cfg_done),
        .manual_evt(manual_evt),.manual_toggle(manual_toggle),
        .stats_sum(stats_sum),.stats_clipped(20'd0),.hold_control(1'b0),.stats_toggle(stats_toggle),.cur_ae(cur_ae),.cur_ag(cur_ag),
        .auto_valid(auto_valid),.auto_req(auto_req),.auto_ae(auto_ae),.auto_ag(auto_ag),
        .frame_cnt(frame_cnt),.silent_cnt(silent_cnt));
    ae_ctrl #(.TARGET_HI(24000),.DEADBAND_HI(1800),.RATE_DIV(8),
              .CLIP_ENTER(4608),.CLIP_EXIT(2304),.AE_MAX(1310),.AG_MAX(152))
        top_dut(.clk(clk),.rst_n(rst_n),.cfg_done(cfg_done),
        .manual_evt(manual_evt),.manual_toggle(manual_toggle),
        .stats_sum(stats_sum),.stats_clipped(20'd0),.hold_control(1'b0),.stats_toggle(stats_toggle),.cur_ae(cur_ae),.cur_ag(cur_ag),
        .auto_valid(top_auto_valid),.auto_req(top_auto_req),.auto_ae(top_auto_ae),.auto_ag(top_auto_ag),
        .frame_cnt(),.silent_cnt());
    task check;
        input [255:0] tag; input cond;
        begin checks=checks+1;
            if(cond!==1'b1) begin errors=errors+1;
                $display("FAIL %0s ae=%0d ag=%0d auto=%b req=%b",tag,auto_ae,auto_ag,auto_valid,auto_req); end
        end
    endtask
    task frame;
        input integer hi;
        begin @(negedge clk); stats_sum=hi<<12; stats_toggle=~stats_toggle;
            repeat(8) @(negedge clk); end
    endtask
    task frames;
        input integer n, hi; integer k;
        begin for(k=0;k<n;k=k+1) frame(hi); end
    endtask
    task seed;
        input integer ae, ag;
        begin cur_ae=ae; cur_ag=ag;
            @(negedge clk); manual_evt=1; repeat(3) @(negedge clk); manual_evt=0;
            frames(299,28800); check("299 frames still manual",!auto_valid);
            frame(28800); check("300th frame rearm exact",auto_valid && auto_ae==ae && auto_ag==ag);
        end
    endtask
    always @(negedge clk) if(rst_n && !test_done) begin
        if(auto_ae<2 || auto_ae>1991 || auto_ag<16 || auto_ag>176) begin
            errors=errors+1; $display("FAIL out of range ae=%0d ag=%0d",auto_ae,auto_ag); end
    end
    initial begin
        repeat(4) @(negedge clk); rst_n=1; repeat(4) @(negedge clk);
        check("default low gain auto",auto_valid && auto_ag==16 && auto_ae==1991);
        check("working exposure cap 1310",top_auto_valid && top_auto_ag==16 && top_auto_ae==1310);
        seed(100,50); frames(3,40000); check("rate first three hold",auto_ae==100);
        frame(40000); check("fourth frame reduces gain first",auto_ae==100 && auto_ag==49);
        frames(4,10000); check("dark restores exposure first",auto_ae==116 && auto_ag==49);
        seed(100,50);
        frames(8,27360); check("lower deadband equality",auto_ae==100 && auto_ag==50);
        frames(8,30240); check("upper deadband equality",auto_ae==100 && auto_ag==50);
        check("no writes in deadband",!auto_req);
        seed(4,16); frames(4,40000); check("floor clamps exactly",auto_ae==2);
        seed(2,50);
        frames(4,40000); check("gain below exposure floor",auto_ag==49);
        frames(4,10000); check("floor reverse resumes exposure",auto_ae==18 && auto_ag==49);
        seed(1990,50); frames(4,10000); check("ceiling clamps exactly",auto_ae==1991);
        frames(4,10000); check("gain above exposure ceiling",auto_ag==51);
        frames(4,40000); check("ceiling reverse lowers gain",auto_ae==1991 && auto_ag==50);
        seed(2,16); frames(16,40000); check("both lower limits hold",auto_ae==2 && auto_ag==16);
        seed(1991,176); frames(16,10000); check("both upper limits hold",auto_ae==1991 && auto_ag==176);
        seed(100,50); cfg_done=0; ae_before=auto_ae; ag_before=auto_ag;
        frames(8,40000); check("outputs frozen busy",auto_ae==ae_before && auto_ag==ag_before && auto_valid);
        @(negedge clk); manual_evt=1; repeat(3) @(negedge clk); manual_evt=0;
        check("ownership frozen busy",auto_valid);
        cfg_done=1; repeat(4) @(negedge clk); check("manual applied after busy",!auto_valid);
        seed(100,50); manual_toggle=~manual_toggle; repeat(7) @(negedge clk);
        check("short press pauses auto",!auto_valid);
        manual_evt=1; frames(320,28800); check("held key prevents rearm",!auto_valid && silent_cnt==0);
        manual_evt=0; frames(300,28800); check("release rearm",auto_valid);
        // Model one payload bit-group being captured one cycle later than the toggle.
        // RTL simulation does not model metastability; this checks the settling window.
        seed(100,50); frames(3,28800);
        @(negedge clk); stats_sum=40000<<12; stats_toggle=~stats_toggle;
        force dut.ssum_1=0;
        @(negedge clk); release dut.ssum_1;
        repeat(8) @(negedge clk);
        check("CDC delayed payload matches event",auto_ae==100 && auto_ag==49);
        // A monotone plant must enter the deadband and stop requesting writes.
        seed(100,16);
        for(i=0;i<180;i=i+1) frame(auto_ae*225);
        check("closed loop converged",auto_ae*225>=27360 && auto_ae*225<=30240);
        ae_before=auto_ae; frames(16,auto_ae*225);
        check("closed loop settled",auto_ae==ae_before && !auto_req);
        // Saturating monotone proxy includes gain, unlike the exposure-only plant.
        seed(1000,144);
        for(i=0;i<1000;i=i+1) begin
            ae_before=auto_ae*auto_ag*20/16;
            frame(ae_before>57375 ? 57375 : ae_before);
        end
        check("bright gain plant reduces amplification first",auto_ag<144 && auto_ae==1000 &&
            auto_ae*auto_ag*20/16>=27360 && auto_ae*auto_ag*20/16<=30240);
        test_done=1;
        if(errors==0) $display("PASS ae_ctrl checks=%0d errors=0",checks);
        else $display("FAIL ae_ctrl checks=%0d errors=%0d",checks,errors);
        $finish;
    end
endmodule
