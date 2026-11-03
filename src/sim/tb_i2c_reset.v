`timescale 1ns/1ps
module tb_i2c_reset;
    reg clk=0, rst_n=0, req=0, slave_low=0;
    wire scl,busy,bus_error;
    tri1 sda;
    wire [7:0] rd_data;
    reg [31:0] wr_data=0;
    reg test_done=0, saw_error=0;
    integer errors=0, transactions=0, reset_checks=0;
    integer phases[0:9];
    integer i;
    always #5 clk=~clk;
    assign sda=slave_low ? 1'b0 : 1'bz;
    uii2c #(.WMEN_LEN(4),.RMEN_LEN(1),.CLK_DIV(239)) dut (
        .I_clk(clk),.I_rstn(rst_n),.O_iic_scl(scl),.IO_iic_sda(sda),
        .I_wr_data(wr_data),.I_wr_cnt(8'd4),.O_rd_data(rd_data),
        .I_rd_cnt(8'd0),.I_iic_req(req),.I_iic_mode(1'b0),
        .O_iic_busy(busy),.O_iic_bus_error(bus_error),.IO_iic_sda_dg()
    );
    always @(posedge bus_error) saw_error=1;
    always @(posedge dut.reset_release_n) begin
        if(clk!==0 || rst_n!==1) begin
            errors=errors+1; $display("FAIL reset released away from parent falling edge");
        end
    end
    task assert_reset;
        begin
            @(negedge clk); #2; rst_n=0; req=0; slave_low=0;
            #1;
            reset_checks=reset_checks+1;
            if({dut.reset_release_n,busy,bus_error,dut.IIC_S} !== 6'd0) begin
                errors=errors+1; $display("FAIL asynchronous reset state");
            end
        end
    endtask
    task release_at_phase;
        input integer phase;
        begin
            // Model the real rst_cnt output: release just after a parent posedge.
            @(posedge clk); #1;
            while ((dut.scl_clk ? 120 : 0)+dut.clkdiv != phase) begin
                @(posedge clk); #1;
            end
            rst_n=1;
            #1;
            if(dut.reset_release_n!==0) begin errors=errors+1; $display("FAIL early release"); end
            @(negedge clk); #1;
            if(dut.reset_release_n!==1) begin errors=errors+1; $display("FAIL missing release"); end
        end
    endtask
    task transaction;
        input ack;
        input [31:0] payload;
        input integer phase;
        integer byte_index,bit_index;
        reg [7:0] received,expected;
        begin
            saw_error=0;
            fork
                begin
                    // Pin-level slave: decode four bytes, then acknowledge or NACK.
                    @(negedge sda);
                    while(scl!==1) @(negedge sda);
                    for(byte_index=0;byte_index<4;byte_index=byte_index+1) begin
                        received=0;
                        for(bit_index=0;bit_index<8;bit_index=bit_index+1) begin
                            @(posedge scl); received={received[6:0],sda};
                        end
                        expected=payload[byte_index*8 +: 8];
                        if(received!==expected) begin
                            errors=errors+1; $display("FAIL I2C byte %0d: %h expected %h",byte_index,received,expected);
                        end
                        @(negedge scl); slave_low=ack;
                        @(posedge scl);
                        @(negedge scl); slave_low=0;
                    end
                end
                begin
                    // Update data and request together just after the parent rising
                    // edge, including edges that toggle the derived SCL clock.
                    @(negedge clk);
                    while ((dut.scl_clk ? 120 : 0)+dut.clkdiv != phase)
                        @(negedge clk);
                    @(posedge clk); #1; wr_data=payload; req=1;
                    @(posedge busy);
                    @(posedge clk); #1; req=0;
                    @(negedge busy);
                end
            join
            repeat(500) @(negedge clk);
            if(busy!==0 || (ack && saw_error) || (!ack && !saw_error)) begin
                errors=errors+1; $display("FAIL I2C completion ack=%b busy=%b error_seen=%b",ack,busy,saw_error);
            end
            transactions=transactions+1;
        end
    endtask
    initial begin
        phases[0]=0; phases[1]=1; phases[2]=59; phases[3]=118; phases[4]=119;
        phases[5]=120; phases[6]=121; phases[7]=179; phases[8]=238; phases[9]=239;
        repeat(3) @(negedge clk);
        for(i=0;i<10;i=i+1) begin
            assert_reset;
            release_at_phase(phases[i]);
            repeat(4) @(negedge clk);
        end
        for(i=0;i<10;i=i+1)
            transaction(1, 32'ha534126c ^ (32'h01030700*i), phases[i]);
        transaction(0,32'h5ac3816c,119);
        // Abort an in-flight transfer, then verify a fresh complete transaction.
        @(negedge clk); req=1;
        wait(dut.IIC_S==2 && dut.bcnt==4);
        assert_reset;
        release_at_phase(120);
        repeat(500) @(negedge clk);
        transaction(1,32'h3ce7186c,239);
        if(transactions!=12 || reset_checks!=11) errors=errors+1;
        test_done=1;
        if(errors==0) $display("PASS i2c_reset reset_checks=%0d transactions=%0d (command-collision/phase/ACK/NACK/abort/restart)",reset_checks,transactions);
        else $display("FAIL i2c_reset errors=%0d",errors);
    end
endmodule
