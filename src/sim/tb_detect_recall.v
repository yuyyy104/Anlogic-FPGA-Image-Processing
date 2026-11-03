`timescale 1ns/1ps
module tb_detect_recall #(parameter TRACK=0,ROW_BLANK=5,FRAME_BLANK=37,N=57,CASE_START=0);
    localparam W=512,H=256,ALL=57;
    reg clk=0,rst=0,de=0,user=0,last=0;always #5 clk=~clk;
    reg [23:0] rgb=0,image[0:W*H-1];reg [31:0] expected[0:ALL*7-1];
    wire valid;wire [1:0] cls;wire [2:0] why;wire [19:0] area;wire [11:0] x0,x1,y0,y1;wire [23:0] fid;
    detect_shape #(.H_ACTIVE(W),.V_ACTIVE(H),.TRACK_BOX(TRACK)) dut(
        .clk(clk),.rst_n(rst),.rgb_in(rgb),.de(de),.user(user),.last(last),
        .res_valid(valid),.res_cls(cls),.res_reason(why),.res_area(area),.res_xmin(x0),.res_xmax(x1),.res_ymin(y0),.res_ymax(y1),.res_frame_id(fid));
    integer errors=0,checks=0,xx,yy,p,old=-1,refcase=-1,hold_count=0,refreason;
    integer cw,ch,pw,ph;reg suspect_ref;reg test_done=0;reg [1023:0] filename;
    wire [97:0] packet={valid,cls,area,x0,x1,y0,y1,fid,why};reg [97:0] prior;
    always @(posedge clk)begin
        #1;if(rst && !test_done)begin checks=checks+1;if(packet!==prior && !user)begin errors=errors+1;$display("FAIL recall packet tore");end end
        prior=packet;
    end
    task verify;
        input integer index;
        begin
            suspect_ref=0;
            if(TRACK && refcase>=0 && expected[refcase*7]!=0 && expected[index*7]!=0)begin
                cw=expected[index*7+3]-expected[index*7+2]+1;ch=expected[index*7+5]-expected[index*7+4]+1;
                pw=expected[refcase*7+3]-expected[refcase*7+2]+1;ph=expected[refcase*7+5]-expected[refcase*7+4]+1;
                suspect_ref=8*expected[index*7+1]>=7*expected[refcase*7+1] && 8*expected[index*7+1]<=9*expected[refcase*7+1] &&
                    (2*cw>3*pw || 2*ch>3*ph);
            end
            if(suspect_ref && hold_count<6)begin hold_count=hold_count+1;refreason=7;end
            else begin refcase=index;hold_count=0;refreason=expected[index*7+6];end
            checks=checks+1;
            if(valid!==(expected[refcase*7]!=0) || cls!==expected[refcase*7] || area!==expected[refcase*7+1] ||
               x0!==expected[refcase*7+2] || x1!==expected[refcase*7+3] || y0!==expected[refcase*7+4] || y1!==expected[refcase*7+5] ||
               why!==refreason || fid!==refcase-CASE_START)begin
                errors=errors+1;$display("FAIL recall case=%0d ref=%0d cls=%0d/%0d area=%0d/%0d bbox=%0d,%0d,%0d,%0d why=%0d/%0d fid=%0d/%0d",
                    index,refcase,cls,expected[refcase*7],area,expected[refcase*7+1],x0,x1,y0,y1,why,refreason,fid,refcase-CASE_START);
            end
        end
    endtask
    initial begin
        $readmemh("D:/codex_project/FPGA_competiton/src/sim/fixtures/shape_recall/expected.mem",expected);
        repeat(4)@(negedge clk);rst=1;
        for(p=0;p<=N;p=p+1)begin
            if(p<N)begin $sformat(filename,"D:/codex_project/FPGA_competiton/src/sim/fixtures/shape_recall/%02d.mem",CASE_START+p);$readmemh(filename,image);end
            for(yy=0;yy<H;yy=yy+1)begin
                for(xx=0;xx<W;xx=xx+1)begin
                    @(negedge clk);de=1;user=xx==0&&yy==0;last=xx==W-1;rgb=p<N?image[yy*W+xx]:24'h303030;
                    if(xx==1&&yy==0&&old>=0)verify(old);
                end
                if(yy<H-1)repeat(ROW_BLANK)begin @(negedge clk);de=0;user=0;last=0;end
            end
            repeat(FRAME_BLANK)begin @(negedge clk);de=0;user=0;last=0;end
            old=CASE_START+p;
        end
        test_done=1;
        if(errors==0)$display("PASS detect_recall cases=%0d start=%0d track=%0d checks=%0d pixels=%0d errors=0",N,CASE_START,TRACK,checks,(N+1)*W*H);
        else $display("FAIL detect_recall errors=%0d",errors);
        $finish;
    end
endmodule
