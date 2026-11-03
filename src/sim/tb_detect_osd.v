`timescale 1ns/1ps
// Unit test for the detection overlay. The expected overlay is recomputed in the
// testbench with plain integer arithmetic (box border, 16-pixel text cells, decimal
// digits via / and %), while the DUT derives the digits with a double-dabble
// converter - the two paths share only the documented layout.
module tb_detect_osd;
    reg clk = 0, rst_n = 0, test_done = 0;
    always #5 clk = ~clk;

    // frame-latched result driven into the DUT
    reg        r_valid = 0;
    reg [1:0]  r_cls   = 0;
    reg [19:0] r_area  = 0;
    reg [11:0] r_xmin = 0, r_xmax = 0, r_ymin = 0, r_ymax = 0;

    reg [11:0] x_2d = 0, y_2d = 0;
    reg        de_2d = 0;
    wire       ov_valid;
    wire [23:0] ov_rgb;

    detect_osd dut (
        .clk(clk), .rst_n(rst_n), .x_2d(x_2d), .y_2d(y_2d), .de_2d(de_2d),
        .res_valid(r_valid), .res_cls(r_cls), .res_area(r_area),
        .res_xmin(r_xmin), .res_xmax(r_xmax), .res_ymin(r_ymin), .res_ymax(r_ymax),
        .ov_valid(ov_valid), .ov_rgb(ov_rgb));

    // reference font for the text glyphs
    reg  [7:0] ch = 0;
    reg  [3:0] fontrow = 0;
    wire [15:0] glyph_ref;
    osd_char_lib ref_font(.I_char(ch), .I_row(fontrow), .O_row_bits(glyph_ref));

    localparam [23:0] COL_RECT = 24'hff2020, COL_CIRC = 24'hffe000;
    localparam [23:0] COL_UNK  = 24'hff00ff, COL_TEXT = 24'h00e6ff;

    integer errors = 0, checks = 0;
    integer ex_v;
    reg [23:0] ex_rgb;
    integer xc6, yc6, dx0, dx1, dy0, dy1, cidx6, col6, dig;
    integer gx, gy;
    reg box_inside, box_border;

    task expect_overlay;
        input integer x6, y6;
        input integer dv;
        begin
            ex_v = 0; ex_rgb = 24'd0;
            // ---- box ----
            box_inside = 0; box_border = 0;
            if (dv && r_valid) begin
                dx0 = r_xmin + 2; dx1 = r_xmax + 2;
                dy0 = r_ymin + 2; dy1 = r_ymax + 2;
                box_inside = (x6 >= dx0) && (x6 <= dx1) && (y6 >= dy0) && (y6 <= dy1);
                box_border = (x6 <= dx0+1) || (x6 >= dx1-1) || (y6 <= dy0+1) || (y6 >= dy1-1);
                if (box_inside && box_border) begin
                    ex_v = 1;
                    ex_rgb = (r_cls == 2) ? COL_RECT : (r_cls == 1) ? COL_CIRC : COL_UNK;
                end
            end
            // ---- text wins where it is lit ----
            xc6 = ((r_xmin + r_xmax + 1) / 2) + 2;
            yc6 = ((r_ymin + r_ymax + 1) / 2) + 2;
            if (dv && r_valid && x6 >= 192 && x6 < 512 && y6 >= 40 && y6 < 56) begin
                col6 = (x6 - 192) % 16;
                cidx6 = (x6 - 192) / 16;
                case (cidx6)
                    0: ch = (r_cls == 2) ? "R" : (r_cls == 1) ? "C" : "U";
                    1: ch = "X";
                    2: ch = 8'h30 + (xc6 / 1000) % 10;
                    3: ch = 8'h30 + (xc6 / 100) % 10;
                    4: ch = 8'h30 + (xc6 / 10) % 10;
                    5: ch = 8'h30 + xc6 % 10;
                    6: ch = " ";
                    7: ch = "Y";
                    8: ch = 8'h30 + (yc6 / 1000) % 10;
                    9: ch = 8'h30 + (yc6 / 100) % 10;
                    10: ch = 8'h30 + (yc6 / 10) % 10;
                    11: ch = 8'h30 + yc6 % 10;
                    12: ch = " ";
                    13: ch = "A";
                    14: ch = 8'h30 + (r_area / 100000) % 10;
                    15: ch = 8'h30 + (r_area / 10000) % 10;
                    16: ch = 8'h30 + (r_area / 1000) % 10;
                    17: ch = 8'h30 + (r_area / 100) % 10;
                    18: ch = 8'h30 + (r_area / 10) % 10;
                    default: ch = 8'h30 + r_area % 10;
                endcase
                fontrow = y6[3:0] - 4'd8;      // y6 - 40, y6 in 40..55
                #1;
                if (glyph_ref[15-col6]) begin
                    ex_v = 1; ex_rgb = COL_TEXT;
                end
            end
        end
    endtask

    task sweep_case;
        input [255:0] tag;
        input integer dv;
        begin
            for (gy = 0; gy <= 80; gy = gy + 1) begin
                for (gx = 0; gx <= 599; gx = gx + 1) begin
                    @(negedge clk);
                    x_2d = gx[11:0]; y_2d = gy[11:0]; de_2d = dv[0];
                    #1;
                    expect_overlay(gx, gy, dv);
                    checks = checks + 1;
                    if (ov_valid !== ex_v[0] || ov_rgb !== ex_rgb) begin
                        errors = errors + 1;
                        if (errors < 12)
                            $display("FAIL %0s at (%0d,%0d) got v=%0d rgb=%h want v=%0d rgb=%h",
                                     tag, gx, gy, ov_valid, ov_rgb, ex_v[0], ex_rgb);
                    end
                end
            end
        end
    endtask

    initial begin
        repeat (4) @(negedge clk);
        rst_n = 1;
        // 1) no target: nothing may be drawn
        r_valid = 0; r_cls = 0; r_area = 0;
        r_xmin = 0; r_xmax = 0; r_ymin = 0; r_ymax = 0;
        repeat (120) @(negedge clk);
        sweep_case("invalid", 1);
        // 2) rectangle, small area
        r_valid = 1; r_cls = 2; r_area = 252; r_xmin = 10; r_xmax = 29; r_ymin = 8; r_ymax = 21;
        repeat (120) @(negedge clk);
        sweep_case("rect", 1);
        // 3) circle
        r_valid = 1; r_cls = 1; r_area = 333; r_xmin = 20; r_xmax = 41; r_ymin = 14; r_ymax = 35;
        repeat (120) @(negedge clk);
        sweep_case("circle", 1);
        // 4) unknown class with a six-digit area, box crossing the text column range
        r_valid = 1; r_cls = 3; r_area = 123456; r_xmin = 150; r_xmax = 420; r_ymin = 30; r_ymax = 70;
        repeat (120) @(negedge clk);
        sweep_case("unknown", 1);
        // 5) blanking: de_2d = 0 while the coordinates sit inside the box and the text
        // row -> nothing may be drawn (contract: both overlays are de-gated)
        r_valid = 1; r_cls = 2; r_area = 252;
        r_xmin = 10; r_xmax = 29; r_ymin = 8; r_ymax = 21;
        repeat (120) @(negedge clk);
        sweep_case("de-low", 0);
        repeat (8) @(negedge clk);
        test_done = 1;
        if (errors == 0) $display("PASS detect_osd checks=%0d cases=5 errors=0", checks);
        else             $display("FAIL detect_osd errors=%0d", errors);
        $finish;
    end
endmodule
