`timescale 1ns/1ps
module tb_color_thresholds;
reg clk=0,rst=0;always #5 clk=~clk;reg [23:0] rgb=0;
wire valid,overflow;wire [7:0] count;wire [11:0] colors,shapes;wire [79:0] areas;wire [191:0] boxes;
color_multitarget #(.H_ACTIVE(512),.V_ACTIVE(256)) dut(.clk(clk),.rst_n(rst),.rgb(rgb),.timing(5'd0),
 .valid(valid),.overflow(overflow),.target_count(count),.colors(colors),.shapes(shapes),.areas(areas),.boxes(boxes));
integer errors=0,checks=0,k;reg test_done=0;
task check;input [23:0] p;input [2:0] expected;begin
 rgb=p;#1;checks=checks+1;
 if(dut.color_id!==expected)begin errors=errors+1;$display("FAIL palette %h id%0d/%0d",p,dut.color_id,expected);end
end endtask
initial begin
 repeat(4)@(negedge clk);rst=1;
 for(k=0;k<256;k=k+1)check({k[7:0],k[7:0],k[7:0]},0);
 check({8'd32,8'd14,8'd14},1);check({8'd100,8'd60,8'd50},1);
 check({8'd30,8'd22,8'd20},1);check({8'd18,8'd8,8'd7},1);check({8'd17,8'd8,8'd7},0);
 check({8'd36,8'd18,8'd10},1);check({8'd80,8'd50,8'd40},1);
 check({8'd90,8'd60,8'd60},1);check({8'd89,8'd60,8'd60},0);
 check({8'd14,8'd32,8'd14},3);check({8'd14,8'd14,8'd32},0);
 check({8'd32,8'd80,8'd40},3);check({8'd40,8'd80,8'd95},0);
 check({8'd32,8'd32,8'd14},2);check({8'd32,8'd32,8'd15},0);
 check({8'd90,8'd60,8'd30},2);check({8'd91,8'd60,8'd30},1);
 check(24'hffffff,0);check(24'hff00ff,0);check(24'h00ffff,0);
 check({8'd90,8'd32,8'd110},0);check({8'd32,8'd80,8'd120},0);
 check({8'd22,8'd12,8'd20},0);check({8'd19,8'd11,8'd18},0);
 check({8'd140,8'd32,8'd190},0);check({8'd190,8'd32,8'd60},1);
 check({8'd40,8'd70,8'd40},3);check({8'd80,8'd70,8'd100},0);
 check({8'd20,8'd60,8'd20},3);check({8'd70,8'd20,8'd48},0);
 check({8'd255,8'd200,8'd200},0);check({8'd255,8'd170,8'd170},1);
 check({8'd250,8'd220,8'd190},0);
 check({8'd255,8'd80,8'd50},1);check({8'd230,8'd80,8'd50},1);
 test_done=1;if(errors==0)$display("PASS color_thresholds checks%0d red_yellow_green purple_background warm_dim_red gray256 ratio4_3 overflow255",checks);else $display("FAIL color_thresholds errors%0d",errors);$finish;
end
endmodule
