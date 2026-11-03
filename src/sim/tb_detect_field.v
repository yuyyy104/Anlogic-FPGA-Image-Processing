`timescale 1ns/1ps
module tb_detect_field #(parameter TRACK=0, ROW_BLANK=5, FRAME_BLANK=37, N=21);
    localparam W=512,H=256;
    reg clk=0,rst=0,de=0,user=0,last=0;always #5 clk=~clk;
    reg [23:0] rgb=0;reg image[0:W*H-1];reg [31:0] expected[0:N*7-1];
    wire valid;wire [1:0] cls;wire [2:0] why;wire [19:0] area;wire [11:0] x0,x1,y0,y1;wire [23:0] fid;
    detect_shape #(.H_ACTIVE(W),.V_ACTIVE(H),.TRACK_BOX(TRACK)) dut(.clk(clk),.rst_n(rst),.rgb_in(rgb),.de(de),.user(user),.last(last),
        .res_valid(valid),.res_cls(cls),.res_reason(why),.res_area(area),.res_xmin(x0),.res_xmax(x1),.res_ymin(y0),.res_ymax(y1),.res_frame_id(fid));
    integer errors=0,checks=0,xx,yy,i,p,old=-1,reference_case,reference_reason;reg test_done=0;reg [1023:0] file_name;
    task verify;
        input integer index;
        begin
            checks=checks+1;
            reference_case=TRACK && index==20?19:index;reference_reason=TRACK && index==20?7:expected[index*7+6];
            if(!valid || cls!==expected[reference_case*7] || area!==expected[reference_case*7+1] ||
               x0!==expected[reference_case*7+2] || x1!==expected[reference_case*7+3] || y0!==expected[reference_case*7+4] || y1!==expected[reference_case*7+5] || why!==reference_reason)begin
                errors=errors+1;$display("FAIL field case=%0d cls=%0d area=%0d bbox=%0d,%0d,%0d,%0d why=%0d expected=%0d/%0d/%0d",index,cls,area,x0,x1,y0,y1,why,expected[index*7],expected[index*7+1],expected[index*7+6]);
            end
        end
    endtask
    initial begin
        $readmemh("D:/codex_project/FPGA_competiton/src/sim/fixtures/shape_field/expected.mem",expected);
        repeat(4)@(negedge clk);rst=1;
        for(p=0;p<=N;p=p+1)begin
            if(p<N)begin $sformat(file_name,"D:/codex_project/FPGA_competiton/src/sim/fixtures/shape_field/%02d.mem",p);$readmemh(file_name,image);end
            for(yy=0;yy<H;yy=yy+1)begin
                for(xx=0;xx<W;xx=xx+1)begin
                    @(negedge clk);de=1;user=(xx==0&&yy==0);last=(xx==W-1);rgb=(p<N && image[yy*W+xx])?24'h6a2f26:24'h303030;
                    if(xx==1&&yy==0&&old>=0)verify(old);
                end
                if(yy<H-1)repeat(ROW_BLANK)begin @(negedge clk);de=0;user=0;last=0;end
            end
            repeat(FRAME_BLANK)begin @(negedge clk);de=0;user=0;last=0;end
            old=p;
        end
        test_done=1;if(errors==0)$display("PASS detect_field cases=%0d checks=%0d pixels=%0d errors=0",N,checks,(N+1)*W*H);else $display("FAIL detect_field errors=%0d",errors);$finish;
    end
endmodule
