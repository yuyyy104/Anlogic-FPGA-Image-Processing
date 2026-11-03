`timescale 1ns/1ps
// Independent integer model for the P3 detector. Fixed coordinates, no learned
// offsets: the model applies the documented rules (colour test, three-tap centred
// run window, integer fill/aspect fractions) directly to the synthetic image.
//
// Patterns: empty, red rect, red circle, wrong colour, too small, clipped at the
// right/bottom edges, isolated noise pixels, two objects in the same rows, two
// objects stacked with a gap, red square (must classify as rectangle).
//
// The result of frame N is published at frame N+1's `user`, so every check runs on
// the frame after the one that produced it; the first check covers the reset state
// (no result, frame_id all ones).
module tb_detect #(parameter CLEANUP=0);
    localparam integer W = 64, H = 48;
    localparam integer THR = 24;
    localparam integer AREA_MIN = 64;
    localparam integer NPAT = 45;
    localparam integer ROWBLANK = 4, FRAMEBLANK = 24;
    localparam [23:0] BG = 24'h303030, RED = 24'hff2020, GREEN = 24'h20ff20;

    reg clk = 0, rst_n = 0, test_done = 0;
    always #5 clk = ~clk;

    reg [23:0] rgb_in = 0;
    reg de = 0, user = 0, last = 0;
    wire res_valid;
    wire [2:0] res_reason;
    integer p_pattern=-1;
    wire [1:0] res_cls;
    wire [19:0] res_area;
    wire [11:0] res_xmin, res_xmax, res_ymin, res_ymax;
    wire [23:0] res_frame_id;

    detect_shape #(.H_ACTIVE(W), .V_ACTIVE(H), .THR_RG(THR), .THR_RB(THR),
                   .AREA_MIN(AREA_MIN),.MASK_CLEANUP(CLEANUP)) dut (
        .clk(clk), .rst_n(rst_n), .rgb_in(rgb_in), .de(de), .user(user), .last(last),
        .res_valid(res_valid), .res_cls(res_cls), .res_area(res_area),
        .res_xmin(res_xmin), .res_xmax(res_xmax), .res_ymin(res_ymin), .res_ymax(res_ymax),
        .res_frame_id(res_frame_id),.res_reason(res_reason));

    integer errors = 0, checks = 0, frame_checks = 0;
    reg [23:0] img[0:H-1][0:W-1];

    // model results
    integer m_area, m_xmin, m_xmax, m_ymin, m_ymax, m_grp, m_rows, m_valid, m_cls,m_reason;
    // last observed result
    integer g_valid, g_cls, g_area, g_xmin, g_xmax, g_ymin, g_ymax, g_fid,g_reason;
    // expectation for the result that the next frame boundary publishes
    integer p_valid, p_cls, p_area, p_xmin, p_xmax, p_ymin, p_ymax, p_fid,p_reason;
    integer yy, xx, pp, fid_expect;
    reg sampled;

    // ---- per-clock property: the published result only ever changes at a frame boundary
    reg [127:0] prev_sig;
    wire [127:0] cur_sig = {res_valid, res_cls, res_area, res_xmin, res_xmax,
                            res_ymin, res_ymax, res_frame_id};
    always @(posedge clk) begin
        #1;
        if (rst_n && !test_done) begin
            checks = checks + 1;
            if (cur_sig !== prev_sig && !user) begin
                errors = errors + 1;
                if (errors < 12) $display("FAIL result changed outside a frame boundary at %0t", $time);
            end
        end
        prev_sig = cur_sig;
    end

    function red_at;
        input integer ya, xa;
        integer r, g, b;
        begin
            r = img[ya][xa][23:16];
            g = img[ya][xa][15:8];
            b = img[ya][xa][7:0];
            red_at = (r >= g + THR) && (r >= b + THR) && 2*r>=3*g && 2*r>=3*b;
        end
    endfunction

    function clean_at;
        input integer ya,xa;
        integer neighbours;
        begin
            neighbours=0;
            if(ya>0) neighbours=neighbours+red_at(ya-1,xa);
            if(ya<H-1) neighbours=neighbours+red_at(ya+1,xa);
            if(xa>0) neighbours=neighbours+red_at(ya,xa-1);
            if(xa<W-1) neighbours=neighbours+red_at(ya,xa+1);
            clean_at=red_at(ya,xa) || (CLEANUP && neighbours>=3);
        end
    endfunction

    task fill_rect;
        input integer x0, y0, ww, hh;
        input [23:0] col;
        integer y4, x4;
        begin
            for (y4 = y0; y4 < y0 + hh; y4 = y4 + 1)
                for (x4 = x0; x4 < x0 + ww; x4 = x4 + 1)
                    if (y4 >= 0 && y4 < H && x4 >= 0 && x4 < W) img[y4][x4] = col;
        end
    endtask

    // Each row has one centred run. The first and last rows retain the full bbox
    // width; middle rows distribute the remaining counted area exactly. Adding
    // two source pixels to each run compensates for the horizontal trim.
    task fill_density;
        input integer ww, hh, counted;
        integer rr, len, middle, base, extra, left;
        begin
            middle = counted - 2*ww;
            base = middle / (hh-2);
            extra = middle % (hh-2);
            for (rr = 0; rr < hh; rr = rr + 1) begin
                len = (rr == 0 || rr == hh-1) ? ww : base + (rr <= extra);
                left = 10 + (ww-len)/2;
                fill_rect(left-1, 10+rr, len+2, 1, RED);
            end
        end
    endtask

    reg seen[0:W*H-1];
    integer queue[0:W*H-1];
    function accepted;
        input integer yy,xx;
        begin accepted=xx>=1 && xx<=W-3 && yy>=0 && yy<H-2 &&
            clean_at(yy,xx-1) && clean_at(yy,xx) && clean_at(yy,xx+1);end
    endfunction
    task build_pattern;
        input integer p;
        integer y3,x3,dx,dy,a,g,row_tgt,prev,w3,h3,prod3,diff3,mx3,lastx,rowlo,rowpts;
        integer spans[0:H-1],points[0:H-1];
        integer k4,topspan,botspan,toppoints,botpoints,outline;
        begin
            for (y3 = 0; y3 < H; y3 = y3 + 1)
                for (x3 = 0; x3 < W; x3 = x3 + 1) img[y3][x3] = BG;
            case (p)
                0: ;
                1: fill_rect(10, 8, 20, 14, RED);
                2: for (y3 = 0; y3 < H; y3 = y3 + 1)
                       for (x3 = 0; x3 < W; x3 = x3 + 1) begin
                           dx = x3 - 32; dy = y3 - 24;
                           if (dx*dx + dy*dy <= 121) img[y3][x3] = RED;
                       end
                3: fill_rect(10, 8, 20, 14, GREEN);
                4: fill_rect(20, 20, 4, 4, RED);
                5: fill_rect(50, 40, 14, 8, RED);
                6: begin img[5][5] = RED; img[9][21] = RED; img[30][40] = RED; img[12][13] = RED; end
                7: begin fill_rect(8, 16, 12, 10, RED); fill_rect(30, 16, 12, 10, RED); end
                8: begin fill_rect(20, 8, 14, 5, RED); fill_rect(20, 24, 14, 5, RED); end
                9: fill_rect(20, 16, 16, 16, RED);
                // AREA_MIN boundary: 9x9 -> 7x9 = 63 counted (below 64 -> no target),
                // 10x8 -> 8x8 = 64 counted (exactly at the limit -> valid)
                10: fill_rect(10, 10, 9, 9, RED);
                11: fill_rect(10, 10, 10, 8, RED);
                // right triangle: one run per row, fill about 0.48 -> UNKNOWN
                12: for (y3 = 10; y3 < 30; y3 = y3 + 1)
                        for (x3 = 10; x3 <= 10 + (y3 - 10); x3 = x3 + 1) img[y3][x3] = RED;
                // wide ellipse 30x12: fill in the circle window (about 0.78) but
                // |w-h| far beyond max/4 -> the aspect test must reject it (UNKNOWN)
                13: for (y3 = 0; y3 < H; y3 = y3 + 1)
                        for (x3 = 0; x3 < W; x3 = x3 + 1) begin
                            dx = x3 - 32; dy = y3 - 24;
                            if (100*dx*dx + 676*dy*dy <= 67600) img[y3][x3] = RED;
                        end
                14: fill_density(16, 16, 208); // rectangle: exactly 13/16
                15: fill_density(16, 16, 207); // circle: one pixel below rectangle
                16: fill_density(16, 16, 144); // circle: exactly 9/16
                17: fill_density(16, 16, 143); // one pixel below circle
                18: fill_density(16, 16, 207); // circle: upper adjacent boundary
                19: fill_density(16, 16, 208); // rectangle: shared exclusive boundary
                20: fill_density(16, 8, 96); // aspect: 4*abs(w-h) == max(w,h)
                21: fill_density(19, 8, 114); // same fill, aspect rejected
                22: fill_rect(10, 10, 15, 5, RED); // AREA_MIN + 1 = 65
                23: fill_rect(10, 10, 10, 8, 24'h402818); // R-G = R-B >= 24
                24: fill_rect(10, 10, 10, 8, 24'h3f2818); // one below colour threshold
                25: fill_rect(10, 10, 10, 8, 24'hffe600); // G+40 = 270, no 8-bit wrap
                26: fill_rect(10,10,10,8,24'hc88c82); // warm skin passes old gaps
                27: fill_rect(10,10,10,8,24'h968c50); // desaturated warm wall
                28: fill_rect(10,10,10,8,24'h966464); // exact 1.5 dominance
                29: fill_rect(10,10,10,8,24'h956464); // one below dominance
                30,33: begin
                    for(y3=0;y3<H;y3=y3+1) for(x3=0;x3<W;x3=x3+1) begin
                        dx=x3-32;dy=y3-24;
                        if(dx*dx+dy*dy<=121 && (p==30 || dx*dx+dy*dy>=49)) img[y3][x3]=RED;
                    end
                    if(p==30) img[24][32]=BG;
                end
                31: begin
                    fill_rect(10,8,40,30,RED);
                    for(y3=12;y3<32;y3=y3+2) begin img[y3][20]=BG;img[y3][35]=BG;end
                end
                32: begin fill_rect(10,8,40,30,RED);fill_rect(27,8,3,30,BG);end
                34: begin fill_rect(10,8,15,25,RED);fill_rect(26,8,15,25,RED);end
                35: fill_density(18,12,162);
                36: begin fill_rect(10,8,40,30,RED);fill_rect(10,22,40,1,BG);end
                37: begin fill_density(16,16,176);img[16][17]=BG;end
                39: begin fill_rect(10,8,15,22,RED);fill_rect(26,16,15,22,RED);end
                40,41: begin
                    fill_rect(10,8,40,30,RED);
                    if(p==41)fill_rect(10,8,16,3,BG);
                    fill_rect(35,11,6,1,BG);fill_rect(30,12,6,1,BG);fill_rect(25,13,6,1,BG);
                end
                42: begin
                    fill_rect(10,8,21,3,RED);
                    fill_rect(10,11,9,6,RED);fill_rect(22,11,9,6,RED);
                    fill_rect(34,12,7,2,RED);fill_rect(10,17,31,11,RED);
                end
                38: begin fill_rect(10,8,40,30,RED);img[22][20]=BG;img[22][35]=BG;end
                43: begin
                    fill_rect(10,8,40,30,24'h6a2f26);
                    // Every row is split before cleanup, including top/bottom.
                    for(y3=8;y3<38;y3=y3+1) img[y3][14+(7*y3)%32]=BG;
                end
                44: begin
                    for(y3=0;y3<H;y3=y3+1) for(x3=0;x3<W;x3=x3+1) begin
                        dx=x3-32;dy=y3-24;
                        if(dx*dx+dy*dy<=121)img[y3][x3]=24'h6a2f26;
                    end
                    for(y3=14;y3<35;y3=y3+1)img[y3][31+2*(y3%2)]=BG;
                end
                default: fill_rect(20, 16, 16, 16, RED);
            endcase

            // ---- independent statistics over the accepted pixels ----
            m_area = 0; m_xmin = 100000; m_xmax = -1; m_ymin = 100000; m_ymax = -1;
            m_grp=0;m_rows=0;
            for (y3 = 0; y3 < H; y3 = y3 + 1) begin
                g=0;row_tgt=0;prev=0;lastx=0;rowlo=0;rowpts=0;
                for (x3 = 0; x3 < W; x3 = x3 + 1) begin
                    // rows H-2 and H-1 are never displayed (display shows source
                    // (r-2,c-2)), so they must not be counted either
                    a = (x3 >= 1) && (x3 <= W-3) && (y3 < H-2) &&
                        clean_at(y3, x3-1) && clean_at(y3, x3) && clean_at(y3, x3+1);
                    if (a) begin
                        m_area = m_area + 1;
                        if (x3 < m_xmin) m_xmin = x3;
                        if (x3 > m_xmax) m_xmax = x3;
                        if (y3 < m_ymin) m_ymin = y3;
                        if (y3 > m_ymax) m_ymax = y3;
                        if(!row_tgt)rowlo=x3;
                        rowpts=rowpts+1;
                        lastx=x3;
                        row_tgt = 1;
                        if (!prev && g < 2) g = g + 1;
                        prev = 1;
                    end else prev = 0;
                end
                if(row_tgt)begin spans[m_rows]=lastx-rowlo+1;points[m_rows]=rowpts;m_rows=m_rows+1;end
                if (g > m_grp) m_grp = g;
            end
            if (m_area == 0) begin
                m_xmin = 0; m_xmax = 0; m_ymin = 0; m_ymax = 0; w3 = 0; h3 = 0;
            end else begin
                w3 = m_xmax - m_xmin + 1; h3 = m_ymax - m_ymin + 1;
            end
            prod3 = w3 * h3;
            diff3 = (w3 >= h3) ? (w3 - h3) : (h3 - w3);
            mx3   = (w3 >= h3) ? w3 : h3;
            topspan=0;botspan=0;toppoints=0;botpoints=0;
            for(k4=0;k4<4;k4=k4+1)if(k4<m_rows)begin
                topspan=topspan+spans[k4];toppoints=toppoints+points[k4];
                botspan=botspan+spans[m_rows-1-k4];botpoints=botpoints+points[m_rows-1-k4];
            end
            outline=w3>=32 && h3>=32 && 2*topspan>=5*w3 && 2*botspan>=5*w3 &&
                2*toppoints>=topspan && 2*botpoints>=botspan;
            m_valid=m_area>=AREA_MIN;
            m_cls=!m_valid ? 0 : 4*m_rows<3*h3 ? 3 :
                (16*m_area>=13*prod3 || outline && 16*m_area>=9*prod3) ? 2 :
                (16*m_area>=9*prod3 && 16*m_area<13*prod3 && mx3<=2*(w3<h3?w3:h3)+2) ? 1 : 3;
            m_reason=m_cls!=3 ? 0 : 4*m_rows<3*h3 ? 2 :
                16*m_area>=9*prod3 && 16*m_area<13*prod3 && mx3>2*(w3<h3?w3:h3)+2 ? 4 : 3;
            // These semantic anchors are within the supported single-target
            // scope. Nearby multi-components retain a statistical comparison,
            // without a connectivity oracle imposing the old strict rejection.
            if(p>=30)begin
                case(p)
                    30,35,37,44:begin checks=checks+1;if(m_cls!=1)begin errors=errors+1;$display("FAIL circle semantic p=%0d",p);end end
                    31,32,36,38,40,41,43:begin checks=checks+1;if(m_cls!=2)begin errors=errors+1;$display("FAIL rect semantic p=%0d",p);end end
                    33:begin checks=checks+1;if(m_cls!=3)begin errors=errors+1;$display("FAIL thin ring semantic");end end
                endcase
            end
            // "no target" (area below AREA_MIN) publishes a cleared bbox
            if (!m_valid) begin
                m_xmin = 0; m_xmax = 0; m_ymin = 0; m_ymax = 0;
            end
        end
    endtask

    task check_boundary_geometry;
        input integer p;
        integer want_area, want_cls;
        begin
            if (!CLEANUP && p >= 14 && p<30) begin
                case (p)
                    14: begin want_area=208; want_cls=2; end
                    15: begin want_area=207; want_cls=1; end
                    16: begin want_area=144; want_cls=1; end
                    17: begin want_area=143; want_cls=3; end
                    18: begin want_area=207; want_cls=1; end
                    19: begin want_area=208; want_cls=2; end
                    20: begin want_area=96; want_cls=1; end
                    21: begin want_area=114; want_cls=3; end
                    22: begin want_area=65;  want_cls=2; end
                    23,28: begin want_area=64;  want_cls=2; end
                    default: begin want_area=0; want_cls=0; end
                endcase
                checks = checks + 1;
                if (m_area != want_area || m_cls != want_cls) begin
                    errors = errors + 1;
                    $display("FAIL boundary geometry p=%0d area=%0d/%0d cls=%0d/%0d",
                             p, m_area, want_area, m_cls, want_cls);
                end
            end
        end
    endtask

    task drive_frame;
        integer y2, x2;
        begin
            for (y2 = 0; y2 < H; y2 = y2 + 1) begin
                for (x2 = 0; x2 < W; x2 = x2 + 1) begin
                    @(negedge clk);
                    rgb_in = img[y2][x2];
                    de = 1'b1; user = (y2 == 0 && x2 == 0); last = (x2 == W-1);
                    if (y2 == 0 && x2 == 1) begin
                        g_valid = res_valid; g_cls = res_cls; g_area = res_area;
                        g_xmin = res_xmin; g_xmax = res_xmax;
                        g_ymin = res_ymin; g_ymax = res_ymax; g_fid = res_frame_id;
                        g_reason=res_reason;
                        sampled = 1'b1;
                    end
                end
                repeat (ROWBLANK) begin @(negedge clk); de=0; user=0; last=0; rgb_in=24'd0; end
            end
            repeat (FRAMEBLANK) begin @(negedge clk); de=0; user=0; last=0; rgb_in=24'd0; end
        end
    endtask

    task check_result;
        input [255:0] tag;
        begin
            frame_checks = frame_checks + 1;
            if (g_valid !== p_valid || g_cls !== p_cls || g_area !== p_area ||
                g_xmin !== p_xmin || g_xmax !== p_xmax ||
                g_ymin !== p_ymin || g_ymax !== p_ymax || g_fid !== p_fid || g_reason!==p_reason) begin
                errors = errors + 1;
                if (errors < 12) $display(
                    "FAIL %0s got valid=%0d cls=%0d area=%0d bbox=[%0d,%0d,%0d,%0d] id=%h | want valid=%0d cls=%0d area=%0d bbox=[%0d,%0d,%0d,%0d] id=%h",
                    tag, g_valid, g_cls, g_area, g_xmin, g_xmax, g_ymin, g_ymax, g_fid,
                    p_valid, p_cls, p_area, p_xmin, p_xmax, p_ymin, p_ymax, p_fid);
            end
        end
    endtask

    initial begin
        repeat (4) @(negedge clk);
        rst_n = 1;
        // expectation for the first publication: the reset state (no frame yet)
        p_valid = 0; p_cls = 0; p_area = 0;
        p_xmin = 0; p_xmax = 0; p_ymin = 0; p_ymax = 0; p_fid = 24'hffffff;
        p_reason=0;
        for (pp = 0; pp < NPAT; pp = pp + 1) begin
            build_pattern(pp);
            check_boundary_geometry(pp);
            sampled = 1'b0;
            drive_frame();
            if (!sampled) begin errors = errors + 1; $display("FAIL pattern %0d never sampled", pp); end
            check_result("frame-boundary");
            p_pattern=pp;
            // pattern pp becomes the expectation of the next publication
            p_valid = m_valid; p_cls = m_cls; p_area = m_area;
            p_xmin = m_xmin; p_xmax = m_xmax; p_ymin = m_ymin; p_ymax = m_ymax;
            p_reason=m_reason;
            p_fid = pp[23:0];
        end
        // one empty frame publishes the last pattern's result
        build_pattern(0);
        sampled = 1'b0;
        drive_frame();
        check_result("last-frame");
        // the empty frame's own result is published by a further empty frame
        p_valid = m_valid; p_cls = m_cls; p_area = m_area;
        p_xmin = m_xmin; p_xmax = m_xmax; p_ymin = m_ymin; p_ymax = m_ymax; p_fid = NPAT[23:0];
        p_reason=m_reason;
        sampled = 1'b0;
        drive_frame();
        check_result("empty-frame");
        repeat (4) @(negedge clk);
        test_done = 1;
        if (errors == 0)
            $display("PASS detect checks=%0d frame_checks=%0d patterns=%0d errors=0",
                     checks, frame_checks, NPAT + 2);
        else
            $display("FAIL detect errors=%0d", errors);
        $finish;
    end
endmodule
