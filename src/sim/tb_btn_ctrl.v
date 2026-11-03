`timescale 1ns/1ps
// KEY1/KEY2 control mode and threshold. KEY3/KEY4 must have no effect.
module tb_btn_ctrl;
    localparam integer DEB_MS = 20;
    localparam integer FAST_HZ = 75000;

    reg clk = 0, rst_n = 0;
    reg [3:0] btn = 4'b1111;
    wire [3:0] mode;
    wire [7:0] thresh;
    integer errors = 0, checks = 0, i;
    reg [7:0] expected_thresh;
    reg test_done = 0;

    always #6.6667 clk = ~clk;

    btn_mode_ctrl #(.CLK_HZ(FAST_HZ), .DEB_MS(DEB_MS)) dut (
        .clk(clk), .rst_n(rst_n), .i_btn(btn),
        .o_mode(mode), .o_thresh(thresh)
    );

    task check;
        input [255:0] tag;
        input cond;
        begin
            checks = checks + 1;
            if (cond !== 1'b1) begin
                errors = errors + 1;
                $display("FAIL %0s mode=%0d thresh=%0d", tag, mode, thresh);
            end
        end
    endtask

    task ms_wait;
        input integer n;
        integer c;
        begin
            c = 0;
            while (c < n) begin
                @(negedge clk);
                if (dut.ms_tick) c = c + 1;
            end
        end
    endtask

    task bounce;
        input integer key;
        integer n;
        begin
            for (n = 0; n < 3; n = n + 1) begin
                btn[key] = 1'b0; ms_wait(1);
                btn[key] = 1'b1; ms_wait(1);
            end
        end
    endtask

    task tap;
        input integer key;
        begin
            bounce(key);
            btn[key] = 1'b0; ms_wait(DEB_MS + 2);
            btn[key] = 1'b1; ms_wait(DEB_MS + 2);
        end
    endtask

    initial begin
        repeat (4) @(negedge clk);
        rst_n = 1;
        ms_wait(2);
        check("reset mode", mode === 4'd0);
        check("reset threshold", thresh === 8'd96);

        // 19 ticks must be rejected; 20 ticks must be accepted.
        bounce(0);
        btn[0] = 1'b0; ms_wait(DEB_MS - 1);
        btn[0] = 1'b1; ms_wait(DEB_MS + 2);
        check("short press rejected", mode === 4'd0);
        tap(0);
        check("mode advances", mode === 4'd1);

        tap(0); check("mode 2", mode === 4'd2);
        tap(0); check("mode 3", mode === 4'd3);
        tap(0); check("mode 5 skips 4", mode === 4'd5);
        tap(0); check("mode 6", mode === 4'd6);
        tap(0); check("mode wraps", mode === 4'd0);

        for (i = 0; i < 8; i = i + 1) begin
            tap(1);
            case (i)
                0: expected_thresh = 8'd128;
                1: expected_thresh = 8'd160;
                2: expected_thresh = 8'd192;
                3: expected_thresh = 8'd224;
                4: expected_thresh = 8'd240;
                5: expected_thresh = 8'd32;
                6: expected_thresh = 8'd64;
                default: expected_thresh = 8'd96;
            endcase
            check("threshold preset", thresh === expected_thresh);
        end
        check("mode kept by threshold key", mode === 4'd0);

        // Removed gain keys: repeated presses never alter mode or threshold.
        tap(2);
        tap(3);
        tap(2);
        check("KEY3 ignored", mode === 4'd0 && thresh === 8'd96);
        check("KEY4 ignored", mode === 4'd0 && thresh === 8'd96);

        btn[0] = 1'b0;
        ms_wait(DEB_MS + 2);
        check("held key acts once", mode === 4'd1);
        ms_wait(1000);
        check("held key does not repeat", mode === 4'd1);
        btn[0] = 1'b1;
        ms_wait(DEB_MS + 2);

        test_done = 1;
        if (errors == 0)
            $display("PASS btn_ctrl checks=%0d KEY1_MODE_KEY2_THRESHOLD_KEY34_DISABLED", checks);
        else
            $display("FAIL btn_ctrl checks=%0d errors=%0d", checks, errors);
        $finish;
    end
endmodule
