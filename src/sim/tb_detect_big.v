`timescale 1ns/1ps
// Large-raster numeric-range test for detect_shape. The functional testbench
// (tb_detect.v) uses a 64x48 raster, so bbox width/height, w*h, area*16 and the
// class comparisons are never exercised anywhere near the real 1280x720 values
// (area up to 921600, area*16 up to 14.7M). This testbench drives the real raster
// with two large objects plus an empty frame.
//
// The independent model derives the accepted pixels from the shape GEOMETRY (per-row
// spans computed analytically), not from the DUT's streaming behaviour: a column x of
// a row with span [lo,hi] is counted iff x-1, x, x+1 are all inside the span and
// 1 <= x <= W-3. Statistics and the class fractions are then recomputed in integers.
module tb_detect_big #(parameter NOISE=0);
    localparam integer W = 1280, H = 720;
    localparam integer AREA_MIN = 64;
    localparam [23:0] BG = 24'h303030, RED = 24'hff2020;
    localparam integer FRAMEBLANK = 32;

    reg clk = 0, rst_n = 0, test_done = 0;
    always #5 clk = ~clk;
    reg [23:0] rgb_in = 0;
    reg de = 0, user = 0, last = 0;
    wire        res_valid;
    wire [1:0]  res_cls;
    wire [19:0] res_area;
    wire [11:0] res_xmin, res_xmax, res_ymin, res_ymax;
    wire [23:0] res_frame_id;

    detect_shape #(.H_ACTIVE(W), .V_ACTIVE(H), .AREA_MIN(AREA_MIN)) dut (
        .clk(clk), .rst_n(rst_n), .rgb_in(rgb_in), .de(de), .user(user), .last(last),
        .res_valid(res_valid), .res_cls(res_cls), .res_area(res_area),
        .res_xmin(res_xmin), .res_xmax(res_xmax), .res_ymin(res_ymin), .res_ymax(res_ymax),
        .res_frame_id(res_frame_id));

    integer errors = 0, checks = 0;
    integer shp, ax0, ay0, aw, ah, acx, acy, arad;
    integer lo, hi;
    integer m_area, m_xmin, m_xmax, m_ymin, m_ymax, m_grp, m_rows, m_valid, m_cls;
    integer g_valid, g_cls, g_area, g_xmin, g_xmax, g_ymin, g_ymax, g_fid;
    integer p_valid, p_cls, p_area, p_xmin, p_xmax, p_ymin, p_ymax, p_fid;
    integer pp, yy, xx, k, r2;
    reg sampled;

    // span of the current shape on row yy: lo..hi inclusive, hi < lo means empty
    task span_for_row;
        input integer yv;
        integer dx, d2;
        begin
            lo = 0; hi = -1;
            case (shp)
                1: if (yv >= ay0 && yv < ay0 + ah) begin lo = ax0; hi = ax0 + aw - 1; end
                2: if (yv >= acy - arad && yv <= acy + arad) begin
                       d2 = arad*arad - (yv - acy)*(yv - acy);
                       dx = 0;
                       for (k = 0; k <= arad; k = k + 1) if (k*k <= d2) dx = k;
                       lo = acx - dx; hi = acx + dx;
                   end
                default: ;
            endcase
        end
    endtask

    // statistics model straight from the spans
    task build_model;
        integer a_lo, a_hi, cnt, gg, row_tgt, prod3, w3, h3, diff3, mx3;
        begin
            m_area = 0; m_xmin = 100000; m_xmax = -1; m_ymin = 100000; m_ymax = -1;
            m_grp = 0; m_rows = 0;
            for (yy = 0; yy < H; yy = yy + 1) begin
                span_for_row(yy);
                // rows H-2 and H-1 are cropped by the display mapping and must not
                // be counted
                if (hi >= lo && yy < H-2) begin
                    a_lo = lo + 1; if (a_lo < 1) a_lo = 1;
                    a_hi = hi - 1; if (a_hi > W - 3) a_hi = W - 3;
                    cnt = (a_hi >= a_lo) ? (a_hi - a_lo + 1) : 0;
                end else cnt = 0;
                if (cnt > 0) begin
                    m_area = m_area + cnt;
                    if (a_lo < m_xmin) m_xmin = a_lo;
                    if (a_hi > m_xmax) m_xmax = a_hi;
                    if (yy  < m_ymin) m_ymin = yy;
                    if (yy  > m_ymax) m_ymax = yy;
                    m_rows = m_rows + 1;
                    if (m_grp < 2) m_grp = 1;   // one contiguous run per row here
                end
            end
            if (m_area == 0) begin
                m_xmin = 0; m_xmax = 0; m_ymin = 0; m_ymax = 0; w3 = 0; h3 = 0;
            end else begin
                w3 = m_xmax - m_xmin + 1; h3 = m_ymax - m_ymin + 1;
            end
            prod3 = w3 * h3;
            diff3 = (w3 >= h3) ? (w3 - h3) : (h3 - w3);
            mx3   = (w3 >= h3) ? w3 : h3;
            m_valid = (m_area >= AREA_MIN) ? 1 : 0;
            m_cls=!m_valid ? 0 : 4*m_rows<3*h3 ? 3 :
                16*m_area>=13*prod3 ? 2 :
                16*m_area>=9*prod3 && 16*m_area<13*prod3 && mx3<=2*(w3<h3?w3:h3)+2 ? 1 : 3;
        end
    endtask

    task drive_frame;
        begin
            for (yy = 0; yy < H; yy = yy + 1) begin
                span_for_row(yy);
                for (xx = 0; xx < W; xx = xx + 1) begin
                    @(negedge clk);
                    rgb_in = (xx >= lo && xx <= hi) ? RED : BG;
                    // Isolated non-red failures throughout each large object,
                    // with moving columns so no straight crack is introduced.
                    if(NOISE && hi-lo>=12 && xx==lo+3+(yy*7)%(hi-lo-5))rgb_in=BG;
                    de = 1'b1; user = (yy == 0 && xx == 0); last = (xx == W-1);
                    if (yy == 0 && xx == 1) begin
                        g_valid = res_valid; g_cls = res_cls; g_area = res_area;
                        g_xmin = res_xmin; g_xmax = res_xmax;
                        g_ymin = res_ymin; g_ymax = res_ymax; g_fid = res_frame_id;
                        sampled = 1'b1;
                    end
                end
            end
            repeat (FRAMEBLANK) begin @(negedge clk); de=0; user=0; last=0; rgb_in=24'd0; end
        end
    endtask

    task check_result;
        input [255:0] tag;
        begin
            checks = checks + 1;
            if (g_valid !== p_valid || g_cls !== p_cls || g_area !== p_area ||
                g_xmin !== p_xmin || g_xmax !== p_xmax ||
                g_ymin !== p_ymin || g_ymax !== p_ymax || g_fid !== p_fid) begin
                errors = errors + 1;
                $display("FAIL %0s got valid=%0d cls=%0d area=%0d bbox=[%0d,%0d,%0d,%0d] id=%h | want valid=%0d cls=%0d area=%0d bbox=[%0d,%0d,%0d,%0d] id=%h",
                    tag, g_valid, g_cls, g_area, g_xmin, g_xmax, g_ymin, g_ymax, g_fid,
                    p_valid, p_cls, p_area, p_xmin, p_xmax, p_ymin, p_ymax, p_fid);
            end
        end
    endtask

    initial begin
        repeat (4) @(negedge clk);
        rst_n = 1;
        p_valid = 0; p_cls = 0; p_area = 0;
        p_xmin = 0; p_xmax = 0; p_ymin = 0; p_ymax = 0; p_fid = 24'hffffff;
        // frame 0: large rectangle 1000 x 600 -> accepted 998 x 600 = 598800
        shp = 1; ax0 = 100; ay0 = 60; aw = 1000; ah = 600;
        build_model; sampled = 1'b0; drive_frame();
        if (!sampled) begin errors = errors + 1; $display("FAIL frame0 never sampled"); end
        check_result("reset-state");
        p_valid = m_valid; p_cls = m_cls; p_area = m_area;
        p_xmin = m_xmin; p_xmax = m_xmax; p_ymin = m_ymin; p_ymax = m_ymax; p_fid = 0;
        $display("  frame0 model: area=%0d cls=%0d bbox=[%0d,%0d,%0d,%0d]", m_area, m_cls, m_xmin, m_xmax, m_ymin, m_ymax);
        // frame 1: large circle, radius 200
        shp = 2; acx = 640; acy = 360; arad = 200;
        build_model; sampled = 1'b0; drive_frame();
        check_result("large-rect");
        p_valid = m_valid; p_cls = m_cls; p_area = m_area;
        p_xmin = m_xmin; p_xmax = m_xmax; p_ymin = m_ymin; p_ymax = m_ymax; p_fid = 1;
        $display("  frame1 model: area=%0d cls=%0d bbox=[%0d,%0d,%0d,%0d]", m_area, m_cls, m_xmin, m_xmax, m_ymin, m_ymax);
        // frame 2: second circle, radius 300 -> w*h about 360000
        shp = 2; acx = 640; acy = 360; arad = 300;
        build_model; sampled = 1'b0; drive_frame();
        check_result("large-circle");
        p_valid = m_valid; p_cls = m_cls; p_area = m_area;
        p_xmin = m_xmin; p_xmax = m_xmax; p_ymin = m_ymin; p_ymax = m_ymax; p_fid = 2;
        $display("  frame2 model: area=%0d cls=%0d bbox=[%0d,%0d,%0d,%0d]", m_area, m_cls, m_xmin, m_xmax, m_ymin, m_ymax);
        // frame 3: rectangle touching the bottom edge (rows 600..719): rows 718/719
        // are not displayable and must be excluded, so ymax must be 717
        shp = 1; ax0 = 200; ay0 = 600; aw = 980; ah = 120;
        build_model; sampled = 1'b0; drive_frame();
        check_result("mid-circle");
        p_valid = m_valid; p_cls = m_cls; p_area = m_area;
        p_xmin = m_xmin; p_xmax = m_xmax; p_ymin = m_ymin; p_ymax = m_ymax; p_fid = 3;
        $display("  frame3 model: area=%0d cls=%0d bbox=[%0d,%0d,%0d,%0d]", m_area, m_cls, m_xmin, m_xmax, m_ymin, m_ymax);
        // frame 4: empty -> publishes frame 3's result
        shp = 0;
        build_model; sampled = 1'b0; drive_frame();
        check_result("bottom-edge-rect");
        p_valid = m_valid; p_cls = m_cls; p_area = m_area;
        p_xmin = m_xmin; p_xmax = m_xmax; p_ymin = m_ymin; p_ymax = m_ymax; p_fid = 4;
        // frame 5: empty -> publishes the empty frame's result
        build_model; sampled = 1'b0; drive_frame();
        check_result("empty");
        repeat (4) @(negedge clk);
        test_done = 1;
        if (errors == 0) $display("PASS detect_big checks=%0d frames=6 errors=0", checks);
        else             $display("FAIL detect_big errors=%0d", errors);
        $finish;
    end
endmodule
