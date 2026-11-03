`timescale 1ns/1ps
module tb_detect_minblank;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,de=0,user=0,last=0;reg [23:0] rgb=0;
    wire valid;wire [1:0] cls;integer checks=0,errors=0;reg test_done=0;
    detect_shape #(.H_ACTIVE(32),.V_ACTIVE(16)) dut(
        .clk(clk),.rst_n(rst),.de(de),.user(user),.last(last),.rgb_in(rgb),
        .res_valid(valid),.res_cls(cls),.res_reason(),.res_area(),.res_xmin(),.res_xmax(),.res_ymin(),.res_ymax(),.res_frame_id());
    task check;input [300:0] name;input ok;
        begin checks=checks+1;if(!ok)begin errors=errors+1;$display("FAIL %s",name);end end
    endtask
    task test_gap;
        input integer blank;
        integer x,y;
        begin
            @(negedge clk);rst=0;de=0;user=0;last=0;repeat(4)@(negedge clk);rst=1;
            for(y=0;y<16;y=y+1)for(x=0;x<32;x=x+1)begin
                @(negedge clk);de=1;user=x==0&&y==0;last=x==31;rgb=24'h6a2f26;
            end
            repeat(blank)begin @(negedge clk);de=0;user=0;last=0;end
            @(negedge clk);
            check("classification ready exactly at contract",dut.publish_valid==(blank==16));
            de=1;user=1;last=0;
            @(negedge clk);de=0;user=0;
            check("sixteen idle beats publish rectangle",blank==15 || valid && cls==2);
        end
    endtask
    initial begin
        test_gap(15);test_gap(16);test_done=1;
        if(errors==0)$display("PASS detect_minblank checks=%0d errors=0",checks);else $display("FAIL detect_minblank errors=%0d",errors);$finish;
    end
endmodule
