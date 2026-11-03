`timescale 1ns/1ps
module tb_color_sample;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,de=0,user=0,last=0,en=0;reg [23:0] rgb=0;
    wire [23:0] mean;wire [12:0] clips;wire valid;
    integer errors=0,checks=0;reg test_done=0;
    color_sample #(.H_ACTIVE(128),.V_ACTIVE(128)) dut(.clk(clk),.rst_n(rst),.de(de),.user(user),.last(last),.enable(en),.rgb(rgb),.mean_rgb(mean),.clip_count(clips),.valid(valid));
    task check;input [255:0] name;input ok;begin checks=checks+1;if(!ok)begin errors=errors+1;$display("FAIL %s",name);end end endtask
    task frame;input [23:0] patch;input integer short_frame;integer x,y;
        begin
            for(y=0;y<128-short_frame;y=y+1)begin
                for(x=0;x<128;x=x+1)begin
                    @(negedge clk);de=1;user=(x==0 && y==0);last=(x==127);
                    rgb=(x>=32 && x<96 && y>=32 && y<96)?patch:24'hffffff;
                end
                @(negedge clk);de=0;user=0;last=0;
            end
            repeat(12)@(negedge clk);
        end
    endtask
    integer n;
    initial begin
        repeat(4)@(negedge clk);rst=1;en=1;
        for(n=0;n<4;n=n+1)frame(24'h206080,0);
        check("wait four complete frames",!valid);
        frame(24'h206080,0);check("mean excludes background and OSD",valid && mean==24'h206080 && clips==0);
        for(n=0;n<9;n=n+1)frame(24'hff5060,0);
        check("one channel clipping counted",valid && mean==24'hff5060 && clips==4096);
        frame(24'h102030,1);frame(24'h102030,0);
        check("short frame invalidates group",!valid);
        en=0;frame(24'h102030,0);check("disabled invalid",!valid);
        test_done=1;if(errors==0)$display("PASS color_sample checks=%0d errors=0",checks);else $display("FAIL color_sample errors=%0d",errors);$finish;
    end
endmodule
