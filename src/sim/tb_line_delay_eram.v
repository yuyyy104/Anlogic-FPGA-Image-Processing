`timescale 1ns/1ps
// Compare against the original active-pixel RAM at one extra clock of latency.
// Run with both the portable model and installed vendor DP/NOREG model.
module line_delay_ref #(parameter integer WIDTH = 1280, parameter integer DW = 8)(
    input wire clk, input wire we, input wire [11:0] col,
    input wire [DW-1:0] din, input wire line_end, output reg [DW-1:0] dout
);
    /* fehdl force_ram=1, ram_style="bram" */
    reg [DW-1:0] mem [0:WIDTH-1];
    wire [11:0] rd_addr = (col == WIDTH-1) ? 12'd0 : col + 12'd1;
    always @(posedge clk) if (we) begin
        dout <= mem[rd_addr];
        mem[col] <= din;
    end
endmodule

module tb_line_delay_eram;
    localparam integer WIDTH = 1280;
    localparam integer DW    = 24;
    localparam integer DLY   = 2;      // one cycle deeper than the original (gated output register)

    reg clk = 0, rst_n = 0, we = 0, line_end = 0;
    reg [11:0] col = 0;
    reg [DW-1:0] din = 0;
    wire [DW-1:0] dout_dut, dout_ref;
    always #5 clk = ~clk;

    line_delay_eram #(.WIDTH(WIDTH), .DW(DW), .AW(11)) dut (
        .clk(clk), .we(we), .col(col), .din(din), .line_end(line_end), .dout(dout_dut));
    line_delay_ref  #(.WIDTH(WIDTH), .DW(DW)) ref (
        .clk(clk), .we(we), .col(col), .din(din), .line_end(line_end), .dout(dout_ref));

    reg [DW-1:0] hist [0:DLY-1];
    integer errors = 0, checks = 0, test_done = 0, i, k, line, gap;

    always @(negedge clk) begin
        for (k = DLY-1; k > 0; k = k - 1) hist[k] = hist[k-1];
        hist[0] = dout_ref;
        // Unwritten memory is masked by preproc; vendor power-up fill may be
        // defined while the original inferred RAM is X. Compare known history.
        if (rst_n && (^hist[DLY-1] !== 1'bx)) begin
            checks = checks + 1;
            if (dout_dut !== hist[DLY-1]) begin
                errors = errors + 1;
                if (errors < 8)
                    $display("FAIL t=%0t we=%b col=%0d dut=%h ref=%h",
                             $time, we, col, dout_dut, hist[DLY-1]);
            end
        end
    end

    task beat;
        input [11:0] c;
        input [DW-1:0] d;
        input le;
        begin
            we = 1'b1; col = c; din = d; line_end = le;
            @(negedge clk);
        end
    endtask

    task blank;
        input integer n;
        begin
            we = 1'b0; line_end = 1'b0;
            for (gap = 0; gap < n; gap = gap + 1) @(negedge clk);
        end
    endtask

    initial begin
        for (k = 0; k < DLY; k = k + 1) hist[k] = {DW{1'bx}};
        repeat (4) @(negedge clk);
        rst_n = 1;
        repeat (2) @(negedge clk);

        for (line = 0; line < 4; line = line + 1) begin
            for (i = 0; i < WIDTH; i = i + 1) begin
                beat(i[11:0], 24'h5a9000 ^ (line << 20) ^ (i * 37), (i == WIDTH-1));
                if (i == 5) blank(3);
            end
            blank(2);
        end

        for (i = 0; i < 6; i = i + 1) begin
            beat((i * 3) % WIDTH, 8'h80 + i, 1'b0);
            if ((i % 2) == 0) blank(1);
        end
        we = 1'b0; line_end = 1'b0;
        repeat (4) @(negedge clk);

        test_done = 1;
        if (checks < 3*WIDTH) errors=errors+1;
        if (errors == 0)
            $display("PASS line_delay_eram checks=%0d dly=%0d errors=0", checks, DLY);
        else
            $display("FAIL line_delay_eram errors=%0d of %0d checks", errors, checks);
        $finish;
    end
endmodule
