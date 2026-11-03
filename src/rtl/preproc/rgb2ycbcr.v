// RGB888 -> full-range YCbCr, three register stages, fixed point.
//
//   Y  = ( 77*R + 150*G +  29*B + 128) >> 8                  range 0..255 (no clamp)
//   Cb = (128*B -  43*R -  85*G + 32896) >> 8, clamped 0..255
//   Cr = (128*R - 107*G -  21*B + 32896) >> 8, clamped 0..255
//
// Coefficients are the BT.601 / JFIF full-range set scaled by 256
// (0.299/0.587/0.114 and -0.169/-0.331/0.5, 0.5/-0.419/-0.081), rounded by +128
// before the shift. Y reuses the exact coefficients of the pre-existing grayscale
// path so the project keeps a single definition of luma.
//
// The +32896 (= 32768 bias + 128 rounding) folds the chroma bias and the signed
// range into one unsigned add: 32768 is a multiple of 256, so (S + 32768) >> 8
// equals (S >> 8) + 128 for the arithmetic shift, and 32768 exceeds the largest
// possible |S| (32640), so the sum never goes negative and no signed arithmetic
// is needed. Result is in 1..256, so only the 256 case is clamped.
//
// Bit growth: products <= 150*255 = 38250; the chroma sums <= 65536 (17 bits).
// Latency is 3 stages for all outputs, so rgb_out/timing_out stay aligned with
// y_out/cb_out/cr_out.
`timescale 1ns / 1ps

module rgb2ycbcr (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [23:0] rgb_in,
    input  wire [4:0]  timing_in,   // {vsync, hsync, de, user, last}
    output reg  [7:0]  y_out,
    output reg  [7:0]  cb_out,
    output reg  [7:0]  cr_out,
    output reg  [23:0] rgb_out,
    output reg  [4:0]  timing_out
);
    wire [15:0] r = {8'd0, rgb_in[23:16]};
    wire [15:0] g = {8'd0, rgb_in[15:8]};
    wire [15:0] b = {8'd0, rgb_in[7:0]};

    // ---- stage 1: constant products by shifts and adds -------------------
    reg [15:0] p_yr, p_yg, p_yb;      //  77R, 150G,  29B
    reg [16:0] p_cbb;                  // 128B
    reg [15:0] p_cbr, p_cbg;           //  43R,  85G
    reg [16:0] p_crr;                  // 128R
    reg [16:0] p_crg, p_crb;           // 107G,  21B
    reg [23:0] rgb_s1;
    reg [4:0]  tim_s1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p_yr <= 0; p_yg <= 0; p_yb <= 0;
            p_cbb <= 0; p_cbr <= 0; p_cbg <= 0;
            p_crr <= 0; p_crg <= 0; p_crb <= 0;
            rgb_s1 <= 24'd0; tim_s1 <= 5'd0;
        end else begin
            p_yr <= (r << 6) + (r << 3) + (r << 2) + r;                   // 77
            p_yg <= (g << 7) + (g << 4) + (g << 2) + (g << 1);            // 150
            p_yb <= (b << 4) + (b << 3) + (b << 2) + b;                   // 29
            p_cbb <= {1'b0, b} << 7;                                      // 128
            p_cbr <= (r << 5) + (r << 3) + (r << 1) + r;                  // 43
            p_cbg <= (g << 6) + (g << 4) + (g << 2) + g;                  // 85
            p_crr <= {1'b0, r} << 7;                                      // 128
            p_crg <= (g << 6) + (g << 5) + (g << 3) + (g << 1) + g;       // 107
            p_crb <= (b << 4) + (b << 2) + b;                             // 21
            rgb_s1 <= rgb_in; tim_s1 <= timing_in;
        end
    end

    // ---- stage 2: unsigned sums ----------------------------------------
    reg [16:0] y_sum;                  // <= 65408
    reg [16:0] cb_sum, cr_sum;         // 256..65536
    reg [23:0] rgb_s2;
    reg [4:0]  tim_s2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y_sum <= 0; cb_sum <= 0; cr_sum <= 0; rgb_s2 <= 24'd0; tim_s2 <= 5'd0;
        end else begin
            y_sum  <= {1'b0, p_yr} + {1'b0, p_yg} + {1'b0, p_yb} + 17'd128;
            cb_sum <= p_cbb + 17'd32896 - {1'b0, p_cbr} - {1'b0, p_cbg};
            cr_sum <= p_crr + 17'd32896 - p_crg - p_crb;
            rgb_s2 <= rgb_s1; tim_s2 <= tim_s1;
        end
    end

    // ---- stage 3: shift, clamp, register -------------------------------
    wire [8:0] cb_sh = cb_sum[16:8];   // 1..256
    wire [8:0] cr_sh = cr_sum[16:8];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y_out <= 8'd0; cb_out <= 8'd0; cr_out <= 8'd0;
            rgb_out <= 24'd0; timing_out <= 5'd0;
        end else begin
            y_out  <= y_sum[15:8];
            cb_out <= (cb_sh > 9'd255) ? 8'd255 : cb_sh[7:0];
            cr_out <= (cr_sh > 9'd255) ? 8'd255 : cr_sh[7:0];
            rgb_out <= rgb_s2;
            timing_out <= tim_s2;
        end
    end
endmodule
