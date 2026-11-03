`timescale 1ns/1ps
module tb_switch_debounce;
    reg clk=0,rst_n=0,raw=0,test_done=0;always #5 clk=~clk;
    wire stable;
    switch_debounce #(.STABLE_CYCLES(8)) dut(.clk(clk),.rst_n(rst_n),.raw(raw),.stable(stable));
    integer errors=0,checks=0,changes=0;reg old=0;
    always @(posedge clk)begin #1;if(rst_n&&!test_done)begin
        checks=checks+1;if(stable!=old)changes=changes+1;old=stable;end end
    task expect;
        input want;
        begin if(stable!==want)begin errors=errors+1;$display("FAIL debounce expected %b got %b",want,stable);end end
    endtask
    initial begin
        repeat(4)@(negedge clk);rst_n=1;
        raw=1;repeat(2)@(negedge clk);raw=0;repeat(12)@(negedge clk);expect(0);
        raw=1;repeat(9)@(negedge clk);expect(0);@(negedge clk);expect(1);
        repeat(10)@(negedge clk);expect(1);
        raw=0;repeat(2)@(negedge clk);raw=1;repeat(12)@(negedge clk);expect(1);
        raw=0;repeat(9)@(negedge clk);expect(1);@(negedge clk);expect(0);
        if(changes!=2)begin errors=errors+1;$display("FAIL debounce changes=%0d",changes);end
        test_done=1;
        if(errors==0)$display("PASS switch_debounce checks=%0d changes=%0d",checks,changes);
        else $display("FAIL switch_debounce errors=%0d",errors);
        $finish;
    end
endmodule
