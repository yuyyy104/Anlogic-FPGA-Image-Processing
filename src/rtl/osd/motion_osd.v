`timescale 1ns/1ps
// P4-c: region overlay for the motion branch.
//
// It draws
//   - one 2-pixel border per region of the top-4 table (slots with area 0 are unused), and
//   - the region count as a BAR LENGTH (count*4 pixels) in a strip no other OSD uses
//     (x 0..31, y 700..703). No font, no BCD, no per-digit comparators.
//
// Coordinates are source GRID CELLS, compensated for the causal-window shift.
// Minimum edges map to 8*cell+2; maximum edges to 8*cell+7+2, clipped.
// Red/orange strip denotes invalid capacity/global-change results respectively.
//
// Priority is decided by the mixer (status bar > P3 detect overlay > this overlay > logo >
// frame counter); this module only produces its own overlay pixels.
module motion_osd #(
    parameter integer H_ACTIVE=1280, V_ACTIVE=720
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        de_2d,                    // display-side active pixel
    input  wire [11:0] x_2d,
    input  wire [11:0] y_2d,
    input  wire        regions_valid,
    input  wire [7:0]  region_count,
    input  wire        regions_overflow, global_change,
    input  wire [15:0] r0_area, r1_area, r2_area, r3_area,
    input  wire [7:0]  r0_xmin, r0_xmax, r0_ymin, r0_ymax,
    input  wire [7:0]  r1_xmin, r1_xmax, r1_ymin, r1_ymax,
    input  wire [7:0]  r2_xmin, r2_xmax, r2_ymin, r2_ymax,
    input  wire [7:0]  r3_xmin, r3_xmax, r3_ymin, r3_ymax,
    output reg         ov_valid,
    output reg  [23:0] ov_rgb
);
    localparam [23:0] BOX_RGB = 24'hff0000;      // all region boxes, one colour
    localparam [23:0] BAR_RGB = 24'h00ff00;      // region-count bar

    // Restore the whole cell footprint before adding the display offset.
    function box_hit;
        input [15:0] area;
        input [7:0]  xmn, xmx, ymn, ymx;
        input [11:0] x, y;
        reg [11:0] x0, x1, y0, y1;
        begin
            x0 = {1'b0,xmn,3'b000} + 12'd2;
            x1 = {1'b0,xmx,3'b000} + 12'd9;
            y0 = {1'b0,ymn,3'b000} + 12'd2;
            y1 = {1'b0,ymx,3'b000} + 12'd9;
            if (x1 >= H_ACTIVE) x1 = H_ACTIVE-1;
            if (y1 >= V_ACTIVE) y1 = V_ACTIVE-1;
            box_hit = (area != 16'd0) &&
                      (x >= x0) && (x <= x1) && (y >= y0) && (y <= y1) &&
                      ((x < x0 + 12'd2) || (x > x1 - 12'd2) ||
                       (y < y0 + 12'd2) || (y > y1 - 12'd2));
        end
    endfunction

    wire box_on = regions_valid &&
                 (box_hit(r0_area, r0_xmin, r0_xmax, r0_ymin, r0_ymax, x_2d, y_2d) ||
                  box_hit(r1_area, r1_xmin, r1_xmax, r1_ymin, r1_ymax, x_2d, y_2d) ||
                  box_hit(r2_area, r2_xmin, r2_xmax, r2_ymin, r2_ymax, x_2d, y_2d) ||
                  box_hit(r3_area, r3_xmin, r3_xmax, r3_ymin, r3_ymax, x_2d, y_2d));

    // count bar: x < count*4 inside the marked strip (x only reaches 31, so it saturates)
    wire bar_zone = (y_2d >= 12'd700) && (y_2d < 12'd704) && (x_2d < 12'd32);
    wire bar_on   = bar_zone && regions_valid && (region_count != 8'd0) &&
                    ({4'd0, x_2d[5:0]} < {2'd0, region_count, 2'b00});

    wire error_on = bar_zone && (regions_overflow || global_change);
    // Combinational, matching the mixer data/coordinates and the P3 overlay.
    always @(*) begin
        ov_valid = rst_n && de_2d && (box_on || bar_on || error_on);
        ov_rgb = error_on ? (regions_overflow ? 24'hff0000 : 24'hff8000) :
                 (box_on ? BOX_RGB : BAR_RGB);
    end
endmodule
