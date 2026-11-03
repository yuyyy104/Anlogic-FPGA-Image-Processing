// Existing ISP line memories use IMG_WIDTH/4 addresses. Keep the synchronous
// READBEFOREWRITE port contract while sizing the physical RAM to those addresses.
module isp_line_store #(parameter integer DW=96, WORDS=320)(
    input wire clk,we,
    input wire [10:0] wa,ra,
    input wire [DW-1:0] data,
    output wire [DW-1:0] q
);
    localparam integer AW=WORDS<=2 ? 1 : $clog2(WORDS);
    localparam integer DEPTH=2**AW;
    PH1P_LOGIC_ERAM #(.DATA_WIDTH_A(DW),.DATA_WIDTH_B(DW),
        .ADDR_WIDTH_A(AW),.ADDR_WIDTH_B(AW),.DATA_DEPTH_A(DEPTH),.DATA_DEPTH_B(DEPTH),
        .BYTE_ENABLE(0),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"),.WRITEMODE_B("READBEFOREWRITE")) ram (
        .clka(clk),.cea(1'b1),.ocea(1'b0),.wea(we),.addra(wa[AW-1:0]),
        .dia(data),.rsta(1'b0),.bea(1'b1),.doa(),
        .clkb(clk),.ceb(1'b1),.oceb(1'b0),.web(1'b0),.addrb(ra[AW-1:0]),
        .dib({DW{1'b0}}),.rstb(1'b0),.beb(1'b1),.dob(q),
        .ecc_sbiterrinj(1'b0),.ecc_dbiterrinj(1'b0),.ecc_sbiterr(),.ecc_dbiterr());
endmodule
