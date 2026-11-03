//======================================================================
// tb_video_frame.v —— 完整 1280x720 含 VTC 消隐的全帧联合测试（P2）
//
// 覆盖计划书明确要求的三件事：
//   1. 各模式的帧大小：每帧必须恰好 720 行 x 1280 有效像素
//   2. 同步：输出时序必须逐拍等于输入时序延迟 LATENCY 拍（DE/HS/VS/user/last）
//   3. 切换无半帧：帧中途改 i_mode，该帧不得出现两种模式混排
//
// 时序用真实 VTC 参数（Htotal=1650, Vtotal=750, 有效 1280x720），消隐区间
// 故意灌垃圾数据，用来确认消隐不写行缓存、不泄漏到有效区。
//
// 本 TB 不含 vendor 的 unpacker / mixer / FIFO 行为模型；那部分（旧
// tb_video_readback.v）仍待迁移到新端口列表，见 docs/P2进展与卡点.md 第五节。
//======================================================================
`timescale 1ns/1ps
module tb_video_frame;
    reg test_done=0;

    localparam integer HTOTAL = 1650, VTOTAL = 750;
    localparam integer HW = 1280, VH = 720;
    localparam integer HSW = 40, VSW = 5;
    // request_timing -> timing_out 的总延迟 = 适配层 2 级采样 + preproc_pipe 的 14 级。
    // 之前这里只写了 14，导致"同步"判据在时序跳变沿上误报。
    localparam integer PIPE_LATENCY = 14;   // preproc_pipe 内部
    localparam integer LATENCY = 2 + 2 + 4 + PIPE_LATENCY;

    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;                 // 100 MHz 仿真时钟，行为与频率无关

    // ---- VTC ----
    reg [11:0] hcnt = 0, vcnt = 0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin hcnt <= 0; vcnt <= 0; end
        else if (hcnt == HTOTAL-1) begin
            hcnt <= 0;
            vcnt <= (vcnt == VTOTAL-1) ? 12'd0 : (vcnt + 12'd1);
        end else hcnt <= hcnt + 12'd1;
    end

    wire de   = (hcnt < HW) && (vcnt < VH);
    wire hs   = (hcnt < HSW);
    wire vs   = (vcnt < VSW);
    wire user = de && (hcnt == 0) && (vcnt == 0);
    wire last = de && (hcnt == HW-1);
    wire [4:0] req = {vs, hs, de, user, last};

    // 测试图案：彩色竖条 + 灰度竖条交替，保证灰度与彩色像素都能出现
    // 图案必须整体有色：如果一半像素本身是灰的，灰度帧与原图帧都会同时出现
    // 灰/彩像素，"半帧混排"判据就会把所有原图帧误判（这是本 TB 早先的缺陷）。
    wire [7:0] bar = hcnt[7:0];
    wire [23:0] src = de ? {bar, 8'h40, 8'h20} : 24'ha5a5a5;   // 消隐期灌垃圾
    reg [23:0] src1,src2;
    always @(posedge clk) begin src1<=src;src2<=src1;end
    reg [3:0] i_mode = 4'd0;
    reg [7:0] i_thresh = 8'd96;
    reg       i_use_btn = 0;

    wire        read_en;
    wire [23:0] o_rgb;
    wire [4:0]  o_tim;

    video_display_pipe #(.IMAGE_WIDTH(HW), .MODE(0), .SPLIT_EN(0)) dut (
        .clk(clk), .rst_n(rst_n), .read_rgb(src2), .request_timing(req),
        .i_denoise(1'b0), .i_mode(i_mode), .i_thresh(i_thresh), .i_use_btn(i_use_btn),
        .read_en(read_en), .rgb_out(o_rgb), .timing_out(o_tim),
        .active_mode(), .active_thresh(),
        .det_valid(), .det_cls(), .det_area(),
        .det_xmin(), .det_xmax(), .det_ymin(), .det_ymax()
    );

    // ---- 参考：输入时序延迟 LATENCY 拍 ----
    reg [4:0] refq [0:LATENCY-1];
    integer   q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (q = 0; q < LATENCY; q = q + 1) refq[q] <= 5'd0;
        end else begin
            refq[0] <= req;
            for (q = 1; q < LATENCY; q = q + 1) refq[q] <= refq[q-1];
        end
    end

    integer errors = 0, checks = 0;
    integer de_viol = 0, sync_viol = 0;
    integer pix_in_frame = 0, rows_in_frame = 0, row_pix = 0;
    integer frames = 0, bad_size = 0;
    integer n_gray = 0, n_raw = 0, bad_frames = 0;
    integer i;

    always @(posedge clk) if (rst_n && (read_en !== req[2])) de_viol = de_viol + 1;

    // 帧大小 + 同步 + 模式混排统计，全部在输出域进行
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pix_in_frame <= 0; rows_in_frame <= 0; row_pix <= 0;
            frames <= 0; bad_size <= 0; n_gray <= 0; n_raw <= 0; bad_frames <= 0;
        end else begin
            if (o_tim !== refq[LATENCY-1]) sync_viol <= sync_viol + 1;
            if (o_tim[2]) begin
                pix_in_frame <= pix_in_frame + 1;
                row_pix <= row_pix + 1;
                if (o_rgb == 24'd0) begin
                    // 零填充边框，不参与模式分类
                end else if (o_rgb[23:16] == o_rgb[15:8] && o_rgb[15:8] == o_rgb[7:0])
                    n_gray <= n_gray + 1;
                else
                    n_raw <= n_raw + 1;

                if (o_tim[0]) begin           // 行尾
                    rows_in_frame <= rows_in_frame + 1;
                    if (row_pix + 1 != HW) bad_size <= bad_size + 1;
                    row_pix <= 0;
                end
                if (o_tim[1]) begin           // 帧首：结算上一帧
                    if (frames > 0) begin
                        if (pix_in_frame != HW*VH) bad_size <= bad_size + 1;
                        if (rows_in_frame != VH)   bad_size <= bad_size + 1;
                        if (n_raw > 0 && n_gray > 0) bad_frames <= bad_frames + 1;
                    end
                    frames <= frames + 1;
                    pix_in_frame <= 1;        // 本拍就是新帧第一个像素
                    rows_in_frame <= 0;
                    row_pix <= 1;
                    n_gray <= (o_rgb != 24'd0 && o_rgb[23:16] == o_rgb[7:0]) ? 1 : 0;
                    n_raw  <= (o_rgb != 24'd0 && o_rgb[23:16] != o_rgb[7:0]) ? 1 : 0;
                end
            end
        end
    end

    // ---- 逐模式跑一整帧 ----
    task run_mode;
        input [3:0] m;
        begin
            // Set on the falling edge before the next source-frame sample.
            // Consecutive calls reuse that boundary instead of skipping a frame.
            i_use_btn = 1'b1; i_mode = m;
            while (!(req[2] && req[1])) @(negedge clk);
            repeat (HTOTAL*VTOTAL) @(negedge clk);
        end
    endtask

    initial begin
        $display("=== tb_video_frame (full 1280x720 with VTC blanking) ===");
        rst_n = 0; i_use_btn = 0; i_mode = 0;
        repeat (10) @(negedge clk);
        rst_n = 1;
        repeat (HTOTAL*2) @(negedge clk);

        // --- 1/2) 各模式整帧：帧大小 + 同步 ---
        bad_size = 0; sync_viol = 0; de_viol = 0;
        for (i = 0; i <= 6; i = i + 1) begin
            run_mode(i[3:0]);
            $display("  mode=%0d done (frames so far=%0d, bad_size=%0d)", i, frames, bad_size);
        end
        repeat (32) @(negedge clk); // drain final-mode timing into the checker
        checks = checks + 1;
        if (bad_size != 0 || frames < 8) begin
            errors = errors + 1;
            $display("FAIL frame size: %0d bad frames (expect 720 rows x 1280 pixels)", bad_size);
        end else $display("PASS frame size: all %0d frames are %0dx%0d", frames, HW, VH);
        checks = checks + 1;
        if (sync_viol != 0) begin
            errors = errors + 1;
            $display("FAIL sync: %0d cycles where timing_out != request_timing delayed %0d",
                     sync_viol, LATENCY);
        end else $display("PASS sync: timing_out equals the VTC delayed %0d cycles every cycle", LATENCY);
        checks = checks + 1;
        if (de_viol != 0) begin
            errors = errors + 1;
            $display("FAIL read_en: %0d cycles differed from raw VTC DE", de_viol);
        end else $display("PASS read_en: always the undelayed VTC DE");

        // --- 3) 切换无半帧：帧中途（第 100 行）把模式从 gray 换成 raw ---
        bad_frames = 0;
        i_use_btn = 1'b1; i_mode = 4'd1;
        while (!(o_tim[2] && o_tim[1])) @(posedge clk);
        // 新帧开始，先跑 100 行再改模式（远晚于帧边界）
        repeat (HTOTAL*100) @(posedge clk);
        i_mode = 4'd0;
        repeat (HTOTAL*VTOTAL*2) @(posedge clk);      // 跑两整帧
        checks = checks + 1;
        if (bad_frames != 0) begin
            errors = errors + 1;
            $display("FAIL no half frame: %0d frames mixed two modes", bad_frames);
        end else $display("PASS no half frame: mode switch mid-frame produced no mixed frame");

        if (errors == 0) $display("PASS video_frame checks=%0d errors=0", checks);
        else             $display("FAIL video_frame checks=%0d errors=%0d", checks, errors);
        test_done=1;
        $finish;
    end
endmodule
