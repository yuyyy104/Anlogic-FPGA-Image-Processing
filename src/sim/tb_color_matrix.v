`timescale 1ns/1ps
module tb_color_matrix;
reg clk=0,rst=0;always #5 clk=~clk;
reg [23:0] rgb=0;reg [4:0] req=0;
wire rd;video_display_pipe #(.IMAGE_WIDTH(128),.V_ACTIVE(16)) dut(
    .clk(clk),.rst_n(rst),.read_rgb(rgb),.request_timing(req),
    .i_mode(4'd0),.i_thresh(8'd96),.i_use_btn(1'b0),.i_denoise(1'b0),.read_en(rd));
`include "D:/codex_project/FPGA_competiton/src/sim/color_matrix_ref.vh"
reg [23:0] wanted;reg [4:0] mq[0:3];
integer checks=0,errors=0,k,r,g,b,n;reg test_done=0;reg [31:0] seed=32'h137925ef;
always @(posedge clk)begin
    if(!rst)begin wanted=0;for(k=0;k<4;k=k+1)mq[k]<=0;end
    else begin
        for(k=3;k>0;k=k-1)mq[k]<=mq[k-1];mq[0]<=req;
        #1;checks=checks+1;
        if(dut.color_rgb!==wanted || dut.color_timing!==mq[3] || rd!==req[2])begin
            errors=errors+1;if(errors<10)$display("FAIL CCM rgb=%h/%h meta=%b/%b",dut.color_rgb,wanted,dut.color_timing,mq[3]);
        end
        wanted=corrected(rgb);
    end
end
task drive;input [23:0] p;
    begin @(negedge clk);rgb=p;seed=(seed>>1)^{32'hd0000001 & {32{seed[0]}}};req=seed[4:0];end
endtask
initial begin
repeat(5)@(negedge clk);rst=1;
for(n=0;n<256;n=n+1)drive({3{n[7:0]}});
for(r=0;r<=256;r=r+8)for(g=0;g<=256;g=g+8)for(b=0;b<=256;b=b+8)
drive({r==256?8'd255:r[7:0],g==256?8'd255:g[7:0],b==256?8'd255:b[7:0]});
for(n=0;n<4096;n=n+1)drive(seed[31:8]);
repeat(5)drive(0);
@(negedge clk);test_done=1;
if(errors==0)$display("PASS color_matrix checks=%0d gray256 grid35937 random4096 signed_round_clip metadata4 raw_read_en errors=0",checks);
else $display("FAIL color_matrix errors=%0d",errors);
$finish;
end
endmodule
