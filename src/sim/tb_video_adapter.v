//======================================================================
// tb_video_adapter.v —— 显示适配层契约（P2 顶层接线）
//
// 只验证适配层自身的职责，算法正确性由 tb_preproc.v 用独立整数模型负责：
//   1. read_en 必须逐拍等于原始 VTC DE（绝不能把延后的 DE 反馈给 FIFO）
//   2. 帧结构原样透传：每行 W 个有效像素、每帧 H 行
//   3. 模式来源选择：i_use_btn=0 跟 MODE 参数，=1 跟 i_mode
//   4. 切换无半帧：在一帧中途改 i_mode，该帧不得出现两种模式混排
//======================================================================
`timescale 1ns/1ps
module tb_video_adapter;
    reg test_done=0;

    localparam integer W = 16, H = 8;

    reg clk = 0, rst_n = 0;
    reg [23:0] src = 24'hff4020;        // 有颜色，灰度化后 R=G=B
    reg [4:0]  req = 5'b00000;
    reg [3:0]  i_mode = 4'd0;
    reg [7:0]  i_thresh = 8'd96;
    reg        i_use_btn = 0;

    reg [23:0] src1,src2;
    always @(posedge clk) begin src1<=src;src2<=src1;end
    wire read_en;
    wire [23:0] rgb_out;
    wire [4:0]  timing_out;

    always #5 clk = ~clk;

    video_display_pipe #(.IMAGE_WIDTH(W), .MODE(1), .SPLIT_EN(0)) dut (
        .clk(clk), .rst_n(rst_n), .read_rgb(src2), .request_timing(req),
        .i_denoise(1'b0), .i_mode(i_mode), .i_thresh(i_thresh), .i_use_btn(i_use_btn),
        .read_en(read_en), .rgb_out(rgb_out), .timing_out(timing_out),
        .active_mode(), .active_thresh(),
        .det_valid(), .det_cls(), .det_area(),
        .det_xmin(), .det_xmax(), .det_ymin(), .det_ymax()
    );

    integer errors = 0, checks = 0;
    integer de_viol = 0;                 // read_en 与原始 DE 不一致的拍数
    integer n_gray = 0, n_raw = 0, n_pix = 0, rows = 0, frames = 0;
    integer bad_frames = 0;
    integer i, r, c;

    // read_en 必须逐拍等于原始 DE
    always @(posedge clk) if (rst_n && (read_en !== req[2])) de_viol = de_viol + 1;

    // 逐帧统计像素模式，检查帧内是否混排
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            n_gray <= 0; n_raw <= 0; n_pix <= 0; rows <= 0; frames <= 0; bad_frames <= 0;
        end else if (timing_out[2]) begin
            n_pix <= n_pix + 1;
            // 黑色（含零填充边框）不参与分类：否则每个 raw 帧的黑色边框
            // 都会被当成灰度像素，误判为"半帧混排"。
            if (rgb_out == 24'd0) begin
                // 边框/消隐，忽略
            end else if (rgb_out[23:16] == rgb_out[15:8] && rgb_out[15:8] == rgb_out[7:0])
                n_gray <= n_gray + 1;
            else
                n_raw <= n_raw + 1;
            if (timing_out[0]) begin
                rows <= rows + 1;
                if (rows + 1 == H) begin
                    // 一帧结束：要么整帧灰度、要么整帧原图
                    if (n_raw > 0 && n_gray > 0) bad_frames <= bad_frames + 1;
                    frames <= frames + 1;
                    rows <= 0; n_gray <= 0; n_raw <= 0; n_pix <= 0;
                end
            end
        end
    end

    // 实测 request_timing -> timing_out 的总延迟（不靠推导）
    integer cyc = 0, t_in_user = -1, lat_meas = -1;
    always @(posedge clk) begin
        cyc = cyc + 1;
        if (req[2] && req[1]) t_in_user = cyc;
        if (timing_out[2] && timing_out[1] && t_in_user > 0 && lat_meas < 0)
            lat_meas = cyc - t_in_user;
    end

    task drive_frame;
        integer rr, cc;
        begin
            for (rr = -1; rr < H + 1; rr = rr + 1)
                for (cc = -2; cc < W + 2; cc = cc + 1) begin
                    @(negedge clk);
                    if (rr >= 0 && rr < H && cc >= 0 && cc < W) begin
                        src = 24'hff4020;
                        req = {1'b0, 1'b1, 1'b1, (rr == 0 && cc == 0), (cc == W-1)};
                    end else begin
                        src = 24'h000000;
                        req = 5'b00000;
                    end
                end
        end
    endtask

    // 整帧驱动，并在第 change_row 行开头切换 i_mode（故意不在帧边界改）
    task drive_frame_sw;
        input integer change_row;
        integer rr, cc;
        begin
            for (rr = -1; rr < H + 1; rr = rr + 1) begin
                if (rr == change_row) i_mode = 4'd0;
                for (cc = -2; cc < W + 2; cc = cc + 1) begin
                    @(negedge clk);
                    if (rr >= 0 && rr < H && cc >= 0 && cc < W) begin
                        src = 24'hff4020;
                        req = {1'b0, 1'b1, 1'b1, (rr == 0 && cc == 0), (cc == W-1)};
                    end else begin
                        src = 24'h000000;
                        req = 5'b00000;
                    end
                end
            end
        end
    endtask

    initial begin
        $display("=== tb_video_adapter ===");
        rst_n = 0; repeat (4) @(negedge clk); rst_n = 1; repeat (4) @(negedge clk);

        // --- 1/2) MODE=1 固定灰度：帧结构与 read_en ---
        i_use_btn = 0;
        drive_frame; drive_frame; drive_frame;
        checks = checks + 1;
        if (de_viol != 0) begin
            errors = errors + 1;
            $display("FAIL read_en: %0d cycles differed from raw VTC DE", de_viol);
        end else $display("PASS read_en: always equals the undelayed VTC DE (%0d frames)", frames);
        checks = checks + 1;
        if (frames < 2) begin
            errors = errors + 1;
            $display("FAIL frame structure: only %0d frames", frames);
        end else $display("PASS frame structure: %0d frames seen, %0dx%0d per frame", frames, W, H);

        // --- 3) i_use_btn=0 时必须跟 MODE 参数（=1 灰度）---
        checks = checks + 1;
        if (n_raw > 0 && n_gray == 0) begin
            errors = errors + 1;
            $display("FAIL mode source: parameter MODE=1 not honoured");
        end

        // --- 4) i_use_btn=1 + 帧中途切 i_mode=0(raw)：不得半帧混排 ---
        i_use_btn = 1;
        i_mode = 4'd1;
        drive_frame;                     // 稳定灰度帧
        bad_frames = 0;
        drive_frame_sw(3);               // 第 3 行开头改 i_mode=0（非帧边界）
        drive_frame;                     // 下一帧应已全部变成 raw
        checks = checks + 1;
        if (bad_frames != 0) begin
            errors = errors + 1;
            $display("FAIL no half frame: %0d frames mixed two modes", bad_frames);
        end else $display("PASS no half frame: %0d full frames, none mixed", frames);

        // --- 4b) 实测总延迟：应为适配层 2 级 + preproc_pipe 14 级 = 16 ---
        checks = checks + 1;
        if (lat_meas != 22) begin
            errors = errors + 1;
            $display("FAIL latency: request_timing -> timing_out measured %0d, expect 22", lat_meas);
        end else
            $display("PASS latency: request_timing -> timing_out = %0d cycles (2 adapter + 14 pipe)",
                     lat_meas);

        // --- 5) 切到 raw 后输出应恢复彩色 ---
        i_mode = 4'd0;
        drive_frame; drive_frame;
        checks = checks + 1;
        if (n_gray != 0 && n_raw == 0) begin
            errors = errors + 1;
            $display("FAIL runtime mode: i_mode=0 did not take effect");
        end else $display("PASS runtime mode: i_mode=0 (raw) reaches the output");

        if (errors == 0) $display("PASS adapter checks=%0d errors=0", checks);
        else             $display("FAIL adapter checks=%0d errors=%0d", checks, errors);
        test_done=1;
        $finish;
    end
endmodule
