`timescale 1ns/1ps
// P3 OSD overlay for the detector result: bounding box plus a result text line.
// Instantiated inside hdmi_mixer so it can reuse that module's two-cycle-delayed
// display coordinates (x_2d / y_2d) and its de_2d: no second coordinate counter is
// needed and the overlay stays pixel-aligned with the video path.
//
// Box: the frame-latched source bbox is mapped to display coordinates (+2 on both
// axes, because display (r,c) shows source (r-2,c-2)) and drawn as a two-pixel
// border. Colour encodes the class: rectangle red, circle yellow, unknown magenta.
// A box narrower than four pixels degenerates into a filled rectangle (documented).
//
// Text: 20 cells of 16x16 pixels starting at x = 192, y = 40:
//     [class][X][4 digits][ ][Y][4 digits][ ][A][6 digits]
// with class '-', 'R', 'C' or 'U'. The decimal digits come from one double-dabble
// converter that is re-run (three values x 20 iterations, about 65 cycles) whenever
// the published result changes, so no divider and no constant division sits in any
// pixel-rate path. Text wins over the box where they overlap.
module detect_osd #(parameter integer READABLE=0) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [11:0] x_2d,
    input  wire [11:0] y_2d,
    input  wire        de_2d,
    input  wire        res_valid,
    input  wire [1:0]  res_cls,
    input  wire [19:0] res_area,
    input  wire [11:0] res_xmin,
    input  wire [11:0] res_xmax,
    input  wire [11:0] res_ymin,
    input  wire [11:0] res_ymax,
    output reg         ov_valid,
    output reg  [23:0] ov_rgb
);
    localparam [23:0] COL_RECT = 24'hff2020;
    localparam [23:0] COL_CIRC = 24'hffe000;
    localparam [23:0] COL_UNK  = 24'hff00ff;
    localparam [23:0] COL_TEXT = 24'h00e6ff;

    localparam [12:0] TEXT_X0 = 13'd192;
    localparam [12:0] TEXT_Y0 = 13'd40;
    localparam [12:0] TEXT_X1 = READABLE ? 13'd736 : 13'd512;   // 20 cells x 16 pixels

    // packed BCD digits, filled by the double-dabble converter below
    reg [23:0] bcd_w, bcd_x, bcd_y, bcd_a;

    // ---------------- display-space geometry ----------------
    wire [12:0] x13 = {1'b0, x_2d};
    wire [12:0] y13 = {1'b0, y_2d};
    wire [12:0] dx0 = {1'b0, res_xmin} + 13'd2;
    wire [12:0] dx1 = {1'b0, res_xmax} + 13'd2;
    wire [12:0] dy0 = {1'b0, res_ymin} + 13'd2;
    wire [12:0] dy1 = {1'b0, res_ymax} + 13'd2;
    // display centre of the source bbox
    wire [12:0] xc  = (({1'b0,res_xmin} + {1'b0,res_xmax} + 13'd1) >> 1) + 13'd2;
    wire [12:0] yc  = (({1'b0,res_ymin} + {1'b0,res_ymax} + 13'd1) >> 1) + 13'd2;

    wire box_inside = (x13 >= dx0) && (x13 <= dx1) && (y13 >= dy0) && (y13 <= dy1);
    wire box_border = (x13 <= dx0 + 13'd1) || (x13 >= dx1 - 13'd1) ||
                      (y13 <= dy0 + 13'd1) || (y13 >= dy1 - 13'd1);
    wire box_on = de_2d && res_valid && box_inside && box_border;
    wire [23:0] box_col = (res_cls == 2'd2) ? COL_RECT :
                          (res_cls == 2'd1) ? COL_CIRC : COL_UNK;

    // ---------------- text line ----------------
    wire [12:0] tx = x13 - TEXT_X0;
    wire [12:0] ty = y13 - TEXT_Y0;
    wire text_region = de_2d && (res_valid || READABLE) &&
                       (x13 >= TEXT_X0) && (x13 < TEXT_X1) &&
                       (y13 >= TEXT_Y0) && (y13 < (TEXT_Y0 + 13'd16));
    wire [5:0] cidx = tx[9:4];

    reg [7:0] tchar;
    generate if(READABLE) begin: g_readable_text
    always @(*) begin
            tchar=0;
            case(cidx)
                0:tchar="S";1:tchar="H";2:tchar="A";3:tchar="P";4:tchar="E";5:tchar=":";
                6:tchar=!res_valid ? "N" : res_cls==2 ? "R" : res_cls==1 ? "C" : "U";
                7:tchar=!res_valid ? "O" : res_cls==2 ? "E" : res_cls==1 ? "I" : "N";
                8:tchar=!res_valid ? "N" : res_cls==2 ? "C" : res_cls==1 ? "R" : "K";
                9:tchar=!res_valid ? "E" : res_cls==2 ? "T" : res_cls==1 ? "C" : "N";
                10:tchar=!res_valid || res_cls==2 ? 0 : res_cls==1 ? "L" : "O";
                11:tchar=!res_valid || res_cls==2 ? 0 : res_cls==1 ? "E" : "W";
                12:tchar=res_valid && res_cls==3 ? "N" : 0;
                14:tchar=res_valid ? "X" : 0;
                15:tchar=res_valid ? "0"+bcd_x[15:12] : 0;
                16:tchar=res_valid ? "0"+bcd_x[11:8] : 0;
                17:tchar=res_valid ? "0"+bcd_x[7:4] : 0;
                18:tchar=res_valid ? "0"+bcd_x[3:0] : 0;
                20:tchar=res_valid ? "Y" : 0;
                21:tchar=res_valid ? "0"+bcd_y[15:12] : 0;
                22:tchar=res_valid ? "0"+bcd_y[11:8] : 0;
                23:tchar=res_valid ? "0"+bcd_y[7:4] : 0;
                24:tchar=res_valid ? "0"+bcd_y[3:0] : 0;
                26:tchar=res_valid ? "A" : 0;
                27:tchar=res_valid ? "0"+bcd_a[23:20] : 0;
                28:tchar=res_valid ? "0"+bcd_a[19:16] : 0;
                29:tchar=res_valid ? "0"+bcd_a[15:12] : 0;
                30:tchar=res_valid ? "0"+bcd_a[11:8] : 0;
                31:tchar=res_valid ? "0"+bcd_a[7:4] : 0;
                32:tchar=res_valid ? "0"+bcd_a[3:0] : 0;
                default:tchar=0;
            endcase
    end
    end else begin: g_legacy_text
    always @(*) begin
        case (cidx)
            5'd0:  tchar = (res_cls == 2'd2) ? 8'h52 : (res_cls == 2'd1) ? 8'h43 : 8'h55;
            5'd1:  tchar = 8'h58;                                  // X
            5'd2:  tchar = 8'h30 + bcd_x[15:12];
            5'd3:  tchar = 8'h30 + bcd_x[11:8];
            5'd4:  tchar = 8'h30 + bcd_x[7:4];
            5'd5:  tchar = 8'h30 + bcd_x[3:0];
            5'd6:  tchar = 8'h20;
            5'd7:  tchar = 8'h59;                                  // Y
            5'd8:  tchar = 8'h30 + bcd_y[15:12];
            5'd9:  tchar = 8'h30 + bcd_y[11:8];
            5'd10: tchar = 8'h30 + bcd_y[7:4];
            5'd11: tchar = 8'h30 + bcd_y[3:0];
            5'd12: tchar = 8'h20;
            5'd13: tchar = 8'h41;                                  // A
            5'd14: tchar = 8'h30 + bcd_a[23:20];
            5'd15: tchar = 8'h30 + bcd_a[19:16];
            5'd16: tchar = 8'h30 + bcd_a[15:12];
            5'd17: tchar = 8'h30 + bcd_a[11:8];
            5'd18: tchar = 8'h30 + bcd_a[7:4];
            default: tchar = 8'h30 + bcd_a[3:0];
        endcase
    end
    end endgenerate
    wire [15:0] glyph;
    osd_char_lib u_font(.I_char(tchar), .I_row(ty[3:0]), .O_row_bits(glyph));
    wire text_on = text_region && glyph[15-tx[3:0]];

    // ---------------- binary to packed BCD (double dabble) ----------------
    function [23:0] dabble;
        input [23:0] v;
        integer k;
        reg [3:0] n;
        begin
            for (k = 0; k < 6; k = k + 1) begin
                n = v[4*k +: 4];
                dabble[4*k +: 4] = (n >= 4'd5) ? (n + 4'd3) : n;
            end
        end
    endfunction

    wire [23:0] dab_next = dabble(bcd_w);   // part-select of a function call is illegal

    wire [71:0] res_now = {res_valid, res_cls, res_area, res_xmin, res_xmax, res_ymin, res_ymax};
    reg  [71:0] res_d;
    wire        res_changed = (res_now !== res_d);

    reg [19:0] acc;
    reg [5:0]  it;
    reg [1:0]  which;
    reg        busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            res_d <= 72'd0;
            busy <= 1'b0; which <= 2'd0; it <= 6'd0; acc <= 20'd0; bcd_w <= 24'd0;
            bcd_x <= 24'd0; bcd_y <= 24'd0; bcd_a <= 24'd0;
        end else begin
            res_d <= res_now;
            if (!busy) begin
                if (res_changed) begin
                    busy <= 1'b1;
                    which <= 2'd0;
                    it <= 6'd0;
                    bcd_w <= 24'd0;
                    acc <= xc;
                end
            end else begin
                bcd_w <= {dab_next[22:0], acc[19]};
                acc   <= {acc[18:0], 1'b0};
                if (it == 6'd19) begin
                    it <= 6'd0;
                    bcd_w <= 24'd0;
                    case (which)
                        2'd0: begin bcd_x <= {dab_next[22:0], acc[19]};
                                     which <= 2'd1; acc <= yc; end
                        2'd1: begin bcd_y <= {dab_next[22:0], acc[19]};
                                     which <= 2'd2; acc <= res_area; end
                        default: begin bcd_a <= {dab_next[22:0], acc[19]};
                                       busy <= 1'b0; end
                    endcase
                end else begin
                    it <= it + 6'd1;
                end
            end
        end
    end

    // ---------------- overlay output ----------------
    always @(*) begin
        if (text_on) begin
            ov_valid = 1'b1;
            ov_rgb   = COL_TEXT;
        end else if (READABLE && text_region) begin
            ov_valid=1'b1;ov_rgb=24'h101820;
        end else if (box_on) begin
            ov_valid = 1'b1;
            ov_rgb   = box_col;
        end else begin
            ov_valid = 1'b0;
            ov_rgb   = 24'd0;
        end
    end
endmodule
