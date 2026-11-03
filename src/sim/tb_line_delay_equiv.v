`timescale 1ns/1ps
module tb_line_delay_equiv;
    reg clk=0;always #5 clk=~clk;
    reg we=0;reg [11:0] col=0;reg [7:0] data=0;
    wire [7:0] q,refq;
    reg test_done=0;integer errors=0,checks=0,row,x,j;
    line_delay #(.WIDTH(1280),.DW(8)) dut(.clk(clk),.we(we),.col(col),.din(data),.line_end(col==1279),.dout(q));
    line_delay_ref #(.WIDTH(1280),.DW(8)) oracle(.clk(clk),.we(we),.col(col),.din(data),.line_end(col==1279),.dout(refq));
    always @(posedge clk)begin #1;
        if(!test_done && (^refq!==1'bx))begin
            checks=checks+1;
            if(q!==refq)begin errors=errors+1;
                if(errors<10)$display("FAIL Y cache row=%0d x=%0d q=%h ref=%h",row,x,q,refq);end
        end
    end
    initial begin
        repeat(5)@(negedge clk);
        for(row=0;row<6;row=row+1)begin
            for(x=0;x<1280;x=x+1)begin
                @(negedge clk);we=1;col=x;data=x*37+row*51;
                if(x==47)begin @(negedge clk);we=0;repeat(3)@(negedge clk);end
            end
            if(row%3!=0)begin @(negedge clk);we=0;repeat(row%3)@(negedge clk);end
        end
        @(negedge clk);we=0;repeat(5)@(negedge clk);
        if(checks<5*1280)errors=errors+1;
        test_done=1;
        if(errors==0)$display("PASS line_delay_equiv checks=%0d width=1280 latency=1",checks);
        else $display("FAIL line_delay_equiv errors=%0d",errors);
        $finish;
    end
endmodule
