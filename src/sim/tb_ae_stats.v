`timescale 1ns/1ps
module tb_ae_stats;
    reg clk=0,rst_n=0,de=0,user=0;
    reg [23:0] rgb=0;
    wire [27:0] stats_sum, hd_sum;
    wire [19:0] stats_n, hd_n;
    wire [19:0] hd_clipped;wire [1:0] hd_local;
    wire stats_toggle,stats_valid,hd_toggle,hd_valid;
    integer errors=0,checks=0,test_done=0,strobes=0,hd_strobes=0,i,k,expected;
    reg [23:0] color;
    reg saved_toggle;
    always #5 clk=~clk;
    ae_stats #(.H_ACTIVE(8),.V_ACTIVE(4)) dut(.clk(clk),.rst_n(rst_n),.de(de),.user(user),
        .rgb(rgb),.stats_sum(stats_sum),.stats_n(stats_n),.stats_toggle(stats_toggle),.stats_valid(stats_valid));
    ae_stats hd(.clk(clk),.rst_n(rst_n),.de(de),.user(user),.rgb(rgb),
        .stats_sum(hd_sum),.stats_n(hd_n),.stats_toggle(hd_toggle),.stats_valid(hd_valid),.stats_clipped(hd_clipped),.stats_local_high(hd_local));
    always @(negedge clk) if(rst_n) begin
        if(stats_valid) strobes=strobes+1;
        if(hd_valid) hd_strobes=hd_strobes+1;
    end
    task check;
        input [255:0] tag; input cond;
        begin checks=checks+1; if(cond!==1'b1) begin errors=errors+1;
            $display("FAIL %0s sum=%0d n=%0d strobes=%0d",tag,stats_sum,stats_n,strobes);end end
    endtask
    task beat;
        input active,first; input [23:0] value;
        begin @(negedge clk);de=active;user=first;rgb=value;@(posedge clk);#1; end
    endtask
    task frame;
        input integer n,style;
        begin expected=0;
            for(k=0;k<n;k=k+1) begin
                if(style==0) color=24'hffffff;
                else if(k==0) color=24'hff0080;
                else if(k==n-1) color=24'h00ff00;
                else color=(((k*37)&255)<<16)|(((k*61)&255)<<8)|((k*17)&255);
                expected=expected+(77*color[23:16]+150*color[15:8]+29*color[7:0]+128)/256;
                beat(1,k==0,color);
                if(k%8==7) beat(0,0,24'hffffff);
            end
            beat(0,0,24'hffffff);
        end
    endtask
    initial begin
        repeat(4) @(negedge clk);rst_n=1;
        repeat(8) beat(1,0,24'hffffff);
        beat(1,1,24'h102030); check("reset fragment rejected",strobes==0 && stats_toggle==0);
        frame(32,1); beat(1,1,0);
        check("first/last pixel and Y exact",stats_sum==expected && stats_n==32 && stats_valid);
        saved_toggle=stats_toggle; repeat(3) beat(0,0,24'hffffff);
        check("single publication pulse",!stats_valid && stats_toggle==saved_toggle && strobes==1);
        frame(31,0); beat(1,1,0);
        check("missing pixel rejected",stats_toggle==saved_toggle && !stats_valid);
        frame(33,0); beat(1,1,0);
        check("extra pixel rejected",stats_toggle==saved_toggle && !stats_valid);
        frame(16,0); @(negedge clk);rst_n=0;@(negedge clk);rst_n=1;
        repeat(16) beat(1,0,24'hffffff); beat(1,1,0);
        check("midframe reset rejected",stats_n==0 && !stats_valid && stats_toggle==0);
        frame(32,0); beat(1,1,0);
        check("first full frame recovers",stats_n==32 && stats_sum==8160 && stats_valid);
        frame(1280*720,0); beat(1,1,0);
        check("HD all-white worst sum",hd_n==921600 && hd_sum==235008000 && hd_valid && hd_clipped==921600 && hd_local==2);
        repeat(3) beat(0,0,0);
        check("HD publication nonvacuous",hd_strobes==1);
        test_done=1;
        if(errors==0)$display("PASS ae_stats checks=%0d hd_sum=%0d errors=0",checks,hd_sum);
        else $display("FAIL ae_stats errors=%0d",errors);
        $finish;
    end
endmodule
