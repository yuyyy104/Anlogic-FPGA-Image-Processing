`timescale 1ns/1ps
// P4 stage 1: 8x8 fixed-phase sampling of the display-side raw pixel stream plus
// the frame difference that produces one bit per cell.
//
// The tap is BEFORE preprocessing: cell (cx,cy) samples SOURCE pixel
// (8*cx,8*cy). The display overlay restores cell coordinates to pixels,
// includes the rest of the 8x8 cell, then applies the display's +2 offset.
//
// Sampling takes the top-left pixel of every CELL x CELL block (phase 0), which
// gives GRID_W x GRID_H = 160 x 90 = 14400 cells per frame. Cell indices follow
// raster order, so the 14-bit cell index is also the frame-store address and no
// multiplier is needed.
//
// Frame flow: each frame writes the bank it scans and reads the other bank. At
// frame end the bank flips and the completed frame's moving-cell count is parked;
// it is published on the next frame's `user`, so the value visible during frame k
// describes the motion of frame k-1 (one frame lag, the same convention as P3).
// After reset the first frame only builds history: mv_valid stays 0 and no count is
// published, so motion is never reported without a real previous frame.
module motion_sample #(
    parameter integer H_ACTIVE = 1280,
    parameter integer V_ACTIVE = 720,
    parameter integer CELL     = 8,      // sampling step on both axes
    parameter integer GRID_W   = 160,    // H_ACTIVE / CELL
    parameter integer GRID_H   = 90,     // V_ACTIVE / CELL
    parameter integer CAW      = 14,     // cell-index width, 2**CAW >= GRID_W*GRID_H
    parameter [7:0]   DIFF_THR = 8'd16   // per-cell absolute difference threshold
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [23:0] rgb_in,
    input  wire        de,
    input  wire        user,          // frame start: first active pixel
    input  wire        last,          // last active pixel of the row
    output reg  [15:0] mv_count,      // moving cells of the last completed frame
    output reg         mv_valid,      // 0 until one full history frame exists
    output reg  [23:0] mv_frame_id,   // frame index the count belongs to
    output wire        mv_cell,       // debug: the cell under comparison is moving
    // cell-rate strobes for the downstream mask/region stages: aligned with mv_cell
    output reg         cell_ce,       // one pulse per compared cell
    output reg         cell_first,    // first cell of a frame
    output reg         cell_row_end,  // last cell of a grid row
    output reg         cell_history   // this cell has a complete preceding frame
);
    localparam integer CELLS   = GRID_W * GRID_H;
    localparam integer AW      = CAW + 1;          // bank offset + cell index
    localparam [CAW-1:0] CELLS_M1 = CELLS - 1;
    // The second bank starts at CELLS, not at 2**CAW: packing the banks that way
    // keeps the store exactly 2*CELLS deep instead of rounding it up to 2**(CAW+1),
    // which would cost extra ERAM blocks for no benefit.
    localparam [AW-1:0] BANK_OFF = CELLS;

    // ---------------- active-raster position counters ----------------
    reg  [11:0] col, row;
    reg capture_active;
    wire [11:0] xi = user ? 12'd0 : col;
    wire [11:0] yi = user ? 12'd0 : row;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin col <= 12'd0; row <= 12'd0; capture_active <= 0; end
        else if (de && (capture_active || user)) begin
            col <= last ? 12'd0 : xi + 12'd1;
            row <= last ? yi + 12'd1 : yi;
            if (user) capture_active <= 1;
            if (last && yi == V_ACTIVE-1) capture_active <= 0;
        end
    end

    // Top-left pixel of every CELL x CELL block. CELL is fixed at 8, so the test is
    // three zero bits and needs no divider.
    wire sample = de && (capture_active || user) &&
                  (xi[2:0] == 3'd0) && (yi[2:0] == 3'd0);

    // ---------------- luma, same coefficients as rgb2ycbcr ----------------
    // 77 = 64+8+4+1, 150 = 128+16+4+2, 29 = 32-4+1: shifts and three adders, no
    // multiplier (the pixel-rate path stays multiplier free).
    wire [15:0] r16 = {8'd0, rgb_in[23:16]};
    wire [15:0] g16 = {8'd0, rgb_in[15:8]};
    wire [15:0] b16 = {8'd0, rgb_in[7:0]};
    wire [15:0] r_term = (r16 << 6) + (r16 << 3) + (r16 << 2) + r16;
    wire [15:0] g_term = (g16 << 7) + (g16 << 4) + (g16 << 2) + (g16 << 1);
    wire [15:0] b_term = (b16 << 5) - (b16 << 2) + b16;
    wire [7:0]  y_pix  = (r_term + g_term + b_term + 16'd128) >> 8;

    // ---------------- cell index, bank and frame accounting ----------------
    reg [CAW-1:0] cell_idx;
    reg           bank;        // bank written by the frame being scanned
    reg           hist;        // the read bank holds a complete previous frame
    reg [15:0]    cell_cnt;    // moving cells counted in the frame being scanned
    reg [23:0]    frame_id;    // index of the frame being scanned
    reg [15:0]    pend_count;
    reg           pend_valid;
    reg [23:0]    pend_id;
    reg [CAW:0]   samples_seen;
    wire [23:0]   next_id = (frame_id == 24'hffffff) ? 24'd0 : frame_id + 24'd1;

    wire frame_end = de && capture_active && last && (yi == V_ACTIVE-1);

    wire [7:0]    rd_data;                       // frame_store read port (1-cycle)
    wire [7:0]    prev = rd_data;
    wire [AW-1:0] cell_a  = user ? {AW{1'b0}} : cell_idx;
    wire [AW-1:0] wr_addr = (bank  ? BANK_OFF : {AW{1'b0}}) + cell_a;
    wire [AW-1:0] rd_addr = (~bank ? BANK_OFF : {AW{1'b0}}) + cell_a;

    reg        sample_d;
    reg [7:0]  y_d;
    wire [8:0] diff = (y_d > prev) ? ({1'b0, y_d} - {1'b0, prev})
                                   : ({1'b0, prev} - {1'b0, y_d});
    wire       mv_move = sample_d && hist && (diff > {1'b0, DIFF_THR});
    assign     mv_cell = mv_move;

    frame_store #(.CELLS(CELLS), .AW(AW)) u_store (
        .clk(clk),
        .wr_en(sample),
        .wr_addr(wr_addr),
        .wr_data(y_pix),
        .rd_addr(rd_addr),
        .rd_data(rd_data)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cell_idx <= {CAW{1'b0}};
        end else if (sample) begin
            cell_idx <= user ? {{(CAW-1){1'b0}},1'b1} :
                        ((cell_idx == CELLS_M1) ? {CAW{1'b0}} : cell_idx + 1'b1);
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_d<=0; y_d<=0; cell_ce<=0; cell_first<=0;
            cell_row_end<=0; cell_history<=0;
        end else begin
        sample_d <= sample; y_d <= y_pix;
        // cell-rate strobes, aligned with mv_cell (one cycle after the anchor pixel)
        cell_ce      <= sample;
        cell_first   <= sample && (xi == 12'd0) && (yi == 12'd0);
        cell_row_end <= sample && (xi == (GRID_W*8 - 8));
        cell_history <= sample && hist && !(user && capture_active);
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bank       <= 1'b0;
            hist       <= 1'b0;
            cell_cnt   <= 16'd0;
            frame_id   <= 24'hffffff;
            pend_count <= 16'd0;
            pend_valid <= 1'b0;
            pend_id    <= 24'hffffff;
            samples_seen <= 0;
        end else if (frame_end) begin
            // The scanned frame is complete: park its result and swap the banks so
            // the next frame reads what this frame just wrote.
            bank       <= ~bank;
            hist       <= (samples_seen == CELLS);
            pend_count <= hist ? cell_cnt : 16'd0;
            pend_valid <= hist && (samples_seen == CELLS);
            frame_id   <= next_id;
            pend_id    <= next_id;
            cell_cnt   <= 16'd0;
            samples_seen <= 0;
        end else begin
            if (de && user) begin
                samples_seen <= 1; cell_cnt <= 0;
                if (capture_active) hist <= 0;
            end else begin
                if (sample) samples_seen <= samples_seen + 1'b1;
                if (mv_move) cell_cnt <= cell_cnt + 16'd1;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mv_count    <= 16'd0;
            mv_valid    <= 1'b0;
            mv_frame_id <= 24'hffffff;
        end else if (user) begin
            mv_count    <= pend_count;
            mv_valid    <= pend_valid;
            // While there is no comparable frame the index must not look like a real
            // frame number (P3 uses the same "no result" marker).
            mv_frame_id <= pend_valid ? pend_id : 24'hffffff;
        end
    end
endmodule
