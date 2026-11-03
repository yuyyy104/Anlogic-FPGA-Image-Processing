`timescale 1ns/1ps
// P4 frame store: the two 160x90 8-bit detection frames (current / previous) in a
// single dual-port block RAM. The address MSB selects the bank, so the ping-pong
// swap is one address bit rather than a frame copy.
//
// Port A (write) captures the bank being scanned; port B (read) delivers the cell
// of the other bank at the same cell index. Both ports are registered here and the
// read data is registered too, so rd_addr presented in cycle N yields rd_data in
// cycle N+1 - a latency that does not depend on how the tool implements the RAM.
//
// The array is intentionally not reset: the caller suppresses cells that have no
// valid history (motion_sample.v), instead of relying on known initial contents.
module frame_store #(
    parameter integer CELLS = 14400,   // 160 * 90 cells per detection frame
    parameter integer AW    = 15       // ceil(log2(2*CELLS))
)(
    input  wire          clk,
    input  wire          wr_en,
    input  wire [AW-1:0] wr_addr,
    input  wire [7:0]    wr_data,
    input  wire [AW-1:0] rd_addr,
    output reg  [7:0]    rd_data
);
    reg [7:0] memory [(2*CELLS)-1:0] /* fehdl force_ram=1, ram_style="bram_fast" */;

    always @(posedge clk) begin
        if (wr_en) memory[wr_addr] <= wr_data;
    end

    always @(posedge clk) begin
        rd_data <= memory[rd_addr];
    end
endmodule
