`timescale 1ns/1ps
module tb_awb_hd;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,valid=0,user=0,last=0;
    reg [95:0] data={4{24'hf0f0f0}};
    integer errors=0,checks=0;reg test_done=0;
    frame_awb #(.REF_R_Q8({5{10'd256}}),.REF_B_Q8({5{10'd256}})) dut(.I_clk(clk),.I_rst_n(rst),.I_tvalid(valid),.I_tuser(user),.I_tlast(last),.I_tdata(data),.I_freeze(1'b0),.I_tready(),.O_tvalid(),.O_tuser(),.O_tlast(),.O_tdata(),.O_tready(1'b1),.O_frozen());
    integer x,y;
    initial begin
        repeat(4)@(negedge clk);rst=1;user=1;@(negedge clk);user=0;
        repeat(8)@(negedge clk);
        for(y=0;y<720;y=y+1)begin
            for(x=0;x<320;x=x+1)begin @(negedge clk);valid=1;last=(x==319);end
            @(negedge clk);valid=0;last=0;repeat(4)@(negedge clk);
        end
        checks=checks+1;
        if(dut.words!=230400 || dut.lines!=720 || dut.line_bad)begin errors=errors+1;$display("FAIL HD geometric gate");end
        for(x=0;x<5;x=x+1)if(dut.counts[x]!=1024 || dut.sums_r[x]!=245760 || dut.sums_g[x]!=245760 || dut.sums_b[x]!=245760)begin errors=errors+1;$display("FAIL HD max statistics patch%0d",x);end
        user=1;@(negedge clk);user=0;repeat(750)@(negedge clk);
        checks=checks+1;if(!dut.pending || dut.pending_r!=256 || dut.pending_b!=256)begin errors=errors+1;$display("FAIL HD divider");end
        test_done=1;if(errors==0)$display("PASS awb_hd checks=%0d pixels=921600 errors=0",checks);else $display("FAIL awb_hd errors=%0d",errors);$finish;
    end
endmodule
