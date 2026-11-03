`timescale 1ns/1ps
module tb_i2c_caller;
    reg clk=0, rst_n=0, ae_req=0, slave_low=0;
    reg test_done=0;
    integer errors=0, transactions=0, round_transactions=0, stable_checks=0;
    reg ae_phase=0, was_busy=0;
    reg [31:0] held_data;
    reg [8:0] reference_index=0;
    wire [31:0] reference_data;
    wire [8:0] reference_size;
    wire scl, cfg_done, ae_done;
    tri1 sda;
    always #5 if (!test_done) clk=~clk;
    assign sda=slave_low ? 1'b0 : 1'bz;
    uicfgcs500_720p #(.CLK_DIV(239)) dut (
        .I_clk(clk),.I_rst_n(rst_n),.I_ae_req(ae_req),
        .I_ae(16'h1234),.I_ag(16'd16),
        .O_cam_scl(scl),.IO_cam_sda(sda),
        .O_cfg_done(cfg_done),.O_ae_cfg_done(ae_done)
    );
    // Independent table index: advance only on decoded pin-level STOP.
    uics500reg_720p60 reference_table (
        .REG_INDEX(reference_index),.REG_DATA(reference_data),.REG_SIZE(reference_size)
    );
    function [23:0] expected_ae;
        input integer n;
        begin
            case(n)
                0: expected_ae=24'h3e0001;
                1: expected_ae=24'h3e0123;
                2: expected_ae=24'h3e0240;
                3: expected_ae=24'h3e0803;
                4: expected_ae=24'h3e0920;
                default: expected_ae=24'hxxxxxx;
            endcase
        end
    endfunction
    always @(posedge clk) begin
        #1;
        if(!rst_n) was_busy=0;
        else begin
            if(dut.iic_busy) begin
                if(was_busy && dut.wr_data!==held_data) begin
                    errors=errors+1; $display("FAIL caller changed data while busy");
                end
                held_data=dut.wr_data;
                stable_checks=stable_checks+1;
            end
            was_busy=dut.iic_busy;
        end
    end
    integer byte_index,bit_index;
    reg [7:0] received,expected_byte;
    reg [23:0] expected_register;
    reg [31:0] expected_word;
    initial forever begin
        @(negedge sda);
        if(rst_n && scl===1 && !test_done) begin
            expected_register=ae_phase ? expected_ae(round_transactions) : reference_data[23:0];
            // Address and register ordering are checked independently of caller wr_data.
            expected_word={expected_register[7:0],expected_register[15:8],expected_register[23:16],8'h6c};
            for(byte_index=0;byte_index<4;byte_index=byte_index+1) begin
                received=0;
                for(bit_index=0;bit_index<8;bit_index=bit_index+1) begin
                    @(posedge scl); received={received[6:0],sda};
                end
                expected_byte=expected_word[byte_index*8 +: 8];
                if(received!==expected_byte) begin
                    errors=errors+1;
                    $display("FAIL caller transaction=%0d byte=%0d actual=%h expected=%h",transactions,byte_index,received,expected_byte);
                end
                @(negedge scl); slave_low=1;
                @(posedge scl);
                @(negedge scl); slave_low=0;
            end
            @(posedge sda);
            while(scl!==1) @(posedge sda);
            transactions=transactions+1;
            round_transactions=round_transactions+1;
            reference_index=reference_index+1'b1;
        end
    end
    initial begin
        repeat(5) @(negedge clk);
        rst_n=1;
        wait(cfg_done);
        if(round_transactions!=116 || reference_size!=116) begin
            errors=errors+1; $display("FAIL init count %0d",round_transactions);
        end
        @(negedge clk); ae_phase=1; round_transactions=0; ae_req=1;
        @(negedge clk); ae_req=0;
        wait(!ae_done); wait(ae_done);
        if(round_transactions!=5) begin
            errors=errors+1; $display("FAIL AE count %0d",round_transactions);
        end
        // Real caller reset must restart the configuration table at entry zero.
        @(negedge clk); rst_n=0; ae_phase=0; reference_index=0; round_transactions=0;
        repeat(20) @(negedge clk);
        rst_n=1;
        wait(round_transactions==4);
        wait(!dut.iic_busy);
        if(transactions!=125 || stable_checks==0) errors=errors+1;
        test_done=1;
        if(errors==0) $display("PASS i2c_caller transactions=%0d stable_checks=%0d (116 init + 5 AE + 4 restart)",transactions,stable_checks);
        else $display("FAIL i2c_caller errors=%0d",errors);
    end
endmodule
