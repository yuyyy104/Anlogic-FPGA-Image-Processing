`timescale 1ns/1ps
module tb_shared_denoise;
    parameter W=16,H=8,FRAMES=12;
    reg clk=0,rst_n=0,test_done=0;
    always #5 clk=~clk;
    reg [23:0] rgb=0;
    reg [4:0] t=0;
    reg enable=0;
    wire [23:0] out;
    wire [4:0] ot;
    wire active,restart;
    shared_denoise #(.IMAGE_WIDTH(W)) dut(.clk(clk),.rst_n(rst_n),.rgb_in(rgb),
        .timing_in(t),.enable(enable),.rgb_out(out),.timing_out(ot),.active_enable(active),.restart(restart));
    integer errors=0,checks=0,f,y,x,k,c,a,b,sum,weight,restarts=0;
    integer samples[0:8],ii,jj,tmp,gaussian;
    reg [23:0] want=0,q[0:3];reg [4:0] tq[0:3];
    reg en_frame=0;
    function [23:0] pixel;
        input integer fr,yy,xx;
        integer rr,gg,bb;
        begin
            if(yy<0||xx<0||yy>=H||xx>=W) pixel=0;
            else if(fr==1) pixel=24'hffffff;
            else if(fr==2) pixel=(xx==W/2 && yy==H/2) ? 24'hffffff : 0;
            else if(fr==4) pixel=(xx+yy)%2 ? 24'h646464 : 24'hc8c8c8;
            else if(fr==6) pixel=(xx*17+yy*23)%37==0 ? 24'hffffff : 24'h808080;
            else if(fr==7) pixel=xx<W/2 ? 24'h000000 : 24'hffffff;
            else if(fr==8) pixel=(xx*43+yy*71)%29==0 ? 24'h000000 : 24'hf02020;
            else if(fr==9) pixel=24'hff80ff;
            else if(fr==10) begin rr=xx*255/(W-1);pixel={3{rr[7:0]}};end
            else if(fr==11) pixel=(xx*13+yy*19)%41==0 ? 24'hffffff : 24'h000000;
            else begin rr=(xx*31+yy*17+fr*51)%256;gg=(xx*13+yy*61+fr)%256;
                bb=(xx*19+yy*41+fr*71)%256;pixel={rr[7:0],gg[7:0],bb[7:0]};end
        end
    endfunction
    task reference;
        reg [23:0] pix;
        begin
            want=0;
            if(t[2]&&y>=1&&x>=1) begin
                if(!en_frame) want=pixel(f,y-1,x-1);
                else for(c=0;c<3;c=c+1) begin
                    sum=0;
                    for(a=0;a<3;a=a+1)for(b=0;b<3;b=b+1)begin
                        weight=(a==1?2:1)*(b==1?2:1);pix=pixel(f,y-2+a,x-2+b);
                        sum=sum+weight*((pix>>(8*c))&255);
                        samples[a*3+b]=(pix>>(8*c))&255;
                    end
                    // Independent full sort of all nine values, rather than
                    // the DUT's staged row-order selection network.
                    for(ii=0;ii<8;ii=ii+1)for(jj=ii+1;jj<9;jj=jj+1)
                        if(samples[ii]>samples[jj])begin tmp=samples[ii];samples[ii]=samples[jj];samples[jj]=tmp;end
                    gaussian=(sum+8)/16;
                    want[8*c +: 8]=(gaussian+samples[4]+1)/2;
                end
            end
        end
    endtask
    always @(posedge clk) begin
        if(!rst_n) for(k=0;k<4;k=k+1)begin q[k]<=0;tq[k]<=0;end
        else begin
            q[0]<=want;tq[0]<=t;
            for(k=1;k<4;k=k+1)begin q[k]<=q[k-1];tq[k]<=tq[k-1];end
        end
        #1;
        if(rst_n&&!test_done) begin
            checks=checks+1;
            if(out!==q[3]||ot!==tq[3])begin
                errors=errors+1;
                if(errors<12)$display("FAIL f=%0d y=%0d x=%0d rgb=%h want=%h timing=%b/%b",f,y,x,out,q[3],ot,tq[3]);
            end
            if(restart)restarts=restarts+1;
        end
    end
    initial begin
        repeat(5)@(negedge clk);rst_n=1;
        for(f=0;f<FRAMES;f=f+1)begin
            en_frame=(f!=0&&f!=3);
            enable=en_frame;
            for(y=0;y<H;y=y+1)begin
                for(x=0;x<W;x=x+1)begin
                    @(negedge clk);t={2'b01,1'b1,(y==0&&x==0),(x==W-1)};
                    rgb=pixel(f,y,x);
                    // Mid-frame changes cannot alter this frame's quality domain.
                    if(y==H/2&&x==W/2)enable=!en_frame;
                    reference;
                end
                repeat(f%3)begin @(negedge clk);t=5'b01000;rgb=0;reference;end
            end
            repeat(f%2)begin @(negedge clk);t=5'b10000;rgb=0;reference;end
        end
        repeat(8)begin @(negedge clk);t=0;rgb=0;reference;end
        if(restarts!=3)begin errors=errors+1;$display("FAIL restarts %0d expected 3",restarts);end
        test_done=1;
        if(errors==0)$display("PASS shared_denoise checks=%0d geometry=%0dx%0d restarts=%0d",checks,W,H,restarts);
        else $display("FAIL shared_denoise errors=%0d",errors);
        $finish;
    end
endmodule
