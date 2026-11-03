// Synchronous NOREG ERAM read plus one gated register: two clocks total.
// The gate preserves the last active prefetch across blanking. Two instances
// replace the raw line delays and their two horizontal alignment registers.
module line_delay_eram #(
    parameter integer WIDTH = 1280,
    parameter integer DW    = 24,
    parameter integer AW    = 11          // 2048 >= WIDTH; 1280x24 fits in 2 ERAM blocks
)(
    input  wire        clk,
    input  wire        we,
    input  wire [11:0] col,
    input  wire [DW-1:0] din,
    input  wire        line_end,
    output reg  [DW-1:0] dout
);
    wire [AW-1:0] wa = col[AW-1:0];
    wire [AW-1:0] ra = (col == WIDTH[11:0]-12'd1) ? {AW{1'b0}} : (col[AW-1:0] + 1'b1);
    wire [DW-1:0] rd_data;
    reg           we_r;

    PH1P_LOGIC_ERAM #(
        .DATA_WIDTH_A (DW),
        .DATA_WIDTH_B (DW),
        .ADDR_WIDTH_A (AW),
        .ADDR_WIDTH_B (AW),
        .BYTE_ENABLE  (0),
        .MODE("DP"), .REGMODE_A("NOREG"), .REGMODE_B("NOREG")
    ) u_ram (
        // port A: synchronous write
        .addra (wa), .dia (din), .cea (1'b1), .ocea (1'b0), .clka (clk), .wea (we),
        .rsta  (1'b0), .bea (1'b1),
        // port B: synchronous read, no additional ERAM output register
        .addrb (ra), .dib ({DW{1'b0}}), .ceb (1'b1), .oceb (1'b1), .clkb (clk), .web (1'b0),
        .rstb  (1'b0), .beb (1'b1),
        .ecc_sbiterrinj (1'b0), .ecc_dbiterrinj (1'b0),
        .doa (), .dob (rd_data), .ecc_sbiterr (), .ecc_dbiterr ()
    );

    // Gated output register: dout follows dob only on active beats and holds during
    // blanking - the same contract as the original module (its read was gated by we).
    // This costs one extra cycle of latency, which preproc_pipe compensates by dropping the
    // two raw_h* stages it used to need.
    always @(posedge clk) begin
        we_r <= we;
        if (we_r) dout <= rd_data;
    end
endmodule
