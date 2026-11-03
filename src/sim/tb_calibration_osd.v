`timescale 1ns/1ps
module tb_calibration_osd;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,fs=0,de=1;reg [11:0] x=0,y=0;
    wire hit;wire [23:0] color;
    integer errors=0,checks=0;reg test_done=0;
    calibration_osd dut(.clk(clk),.rst_n(rst),.frame_start(fs),.de(de),.x(x),.y(y),.lock_exposure(1'b1),.freeze_wb(1'b1),.enable(1'b1),.sample_valid(1'b1),.mean_rgb(24'hff6080),.clip_count(13'd4096),.shape_w(12'd1280),.shape_h(12'd720),.reason(3'd4),.hit(hit),.color(color));
    task check;input [255:0] name;input ok;begin checks=checks+1;if(!ok)begin errors=errors+1;$display("FAIL %s",name);end end endtask
    initial begin
        repeat(4)@(negedge clk);rst=1;fs=1;@(negedge clk);fs=0;repeat(90)@(negedge clk);
        check("decimal conversion exact",dut.digits[0]==16'h0255 && dut.digits[1]==16'h0096 && dut.digits[2]==16'h0128 && dut.digits[3]==16'h4096 && dut.digits[4]==16'h1280 && dut.digits[5]==16'h0720);
        y=88;x=192+5*16;#1;check("LOCK shown",hit && dut.ch=="1");
        x=192+10*16;#1;check("WB shown",hit && dut.ch=="1");
        x=192+16*16;#1;check("CAL shown",hit && dut.ch=="1");
        y=112;x=192+2*16;#1;check("R hundreds",hit && dut.ch=="2");
        x=192+26*16;#1;check("clip units",hit && dut.ch=="6");
        y=136;x=192+18*16;#1;check("reason digit",hit && dut.ch=="4");
        x=611;y=331;#1;check("raw-source patch mapping",hit && color==24'h00ffff);
        x=612;y=332;#1;check("patch interior untouched",!hit);
        test_done=1;if(errors==0)$display("PASS calibration_osd checks=%0d errors=0",checks);else $display("FAIL calibration_osd errors=%0d",errors);$finish;
    end
endmodule
