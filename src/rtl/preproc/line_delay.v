// Active-pixel line delay, WIDTH >= 2. col advances only on we and wraps at WIDTH.
// The last active beat prefetches column 0 for the next line. Both read and write
// pause in blanking so this prefetch is preserved. No same-address read/write.
// RAM is not reset: the caller masks rows not yet written in the current frame.
module line_delay #(parameter integer WIDTH=1280, parameter integer DW=8)(
    input wire clk, input wire we, input wire [11:0] col,
    input wire [DW-1:0] din, input wire line_end, output wire [DW-1:0] dout
);
    localparam integer AW=(WIDTH<=2)?1:$clog2(WIDTH);
    wire [AW-1:0] rd_addr=(col==WIDTH-1)?{AW{1'b0}}:col[AW-1:0]+1'b1;
    // NOREG is the synchronous memory read itself, with no extra output flop.
    // Gating its read clock-enable preserves the active-pixel prefetch in blanking.
    PH1P_LOGIC_ERAM #(.DATA_WIDTH_A(DW),.DATA_WIDTH_B(DW),
        .ADDR_WIDTH_A(AW),.ADDR_WIDTH_B(AW),.DATA_DEPTH_A(WIDTH),.DATA_DEPTH_B(WIDTH),
        .BYTE_ENABLE(0),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG")) ram (
        .clka(clk),.cea(1'b1),.ocea(1'b0),.wea(we),.addra(col[AW-1:0]),
        .dia(din),.rsta(1'b0),.bea(1'b1),.doa(),
        .clkb(clk),.ceb(we),.oceb(1'b1),.web(1'b0),.addrb(rd_addr),
        .dib({DW{1'b0}}),.rstb(1'b0),.beb(1'b1),.dob(dout),
        .ecc_sbiterrinj(1'b0),.ecc_dbiterrinj(1'b0),.ecc_sbiterr(),.ecc_dbiterr());
endmodule
