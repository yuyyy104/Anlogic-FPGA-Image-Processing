//======================================================================
// tb_sc520_config.v —— SC520CS 配置流程功能验证（P1）
//
// 被测：uics520_cfg/uicfgcs520.v（+ 共用 uics500_cfg/uii2c.v）
//
// 总线地址约定（本 TB 的关键前提，曾导致 P1 卡点）：
//   官方 SC500/SC520 示例的 CAM_ID=8'h6c 是**直接送到总线上的第一个字节**，
//   即 7 位从机地址 0x36 的写地址；读事务为 0x6d。依据：
//     vendor/baseline/lab_ex3_osd/.../uics500_cfg/uicfgcs500.v:101
//     prj/td/lab_ex3_sc520/.../uics520_cfg/uicfgcs520.v:155  wr_data[7:0] <= CAM_ID
//   两者一致。不要写成 byte_addr[7:1]==7'h6c（那是把 CAM_ID 当成 7 位地址）。
//
// 从机模型：引脚级、按字节真实收发，不预设内部 busy / rd_data。
//   用父钟轮询而非 @(posedge scl)：主机事务中途复位时事件等待会把从机卡死，
//   而 P1 要求覆盖「事务中复位 + 完整重启」。
//
// 覆盖（15 项检查，全部有独立期望值；失败用例同时断言"确实发生了预期的失败"）：
//   S1/S2 合法 ID ee4b / 9e4b（同时比对 sensor_id 本体）；S3 非法 ID（必须进 ST_ERROR）；
//   S4 地址 NACK；S5 无摄像头；S6 数据字节 NACK（165 条写完后 cfg_done 仍按厂商语义为 1，
//      但诚实信号 O_cfg_ok 必须为 0）；
//   S7 事务中复位（复位前断言 busy 为高）后完整重启；
//   S8 完整序列：165 条初始化逐条顺序+内容、首条软复位后 5 ms 等待、
//      8 条 AE 逐条顺序+内容、cfg_done / ae_cfg_done / O_cfg_ok 完成标志；
//   读事务寄存器低字节限定 0x07/0x08；busy 期间命令稳定（uii2c 数据契约）。
//
// 方案 C（用户 2026-09-29 决定）：O_cfg_done / O_ae_cfg_done 保持厂商语义（表走完即抬起），
//   因为它们经 design_top_wrapper.v → ae_set.v:117 门控 AE/AG 按键写入；若直接门控会被
//   一次 NACK 永久锁死。另有 O_cfg_ok = O_cfg_done & ~O_iic_error 专供指示，失败时恒为 0。
//
// 不覆盖（留给 H 上板）：真实传感器 ID、电气特性、PWDNB/XSHUTDN 上电时序
//   （该部分在顶层上电电路，不在 uicfgcs520 内）。
//======================================================================
`timescale 1ns/1ps

module tb_sc520_config #(parameter integer PQ_TEST=0);
    reg [1:0] pq_ag_toggle=2'b00;
    reg pq_manual_toggle=0, pq_stats_toggle=0;
    reg [27:0] pq_sum=28'd117964800;
    wire pq_req,pq_auto;
    wire [15:0] pq_ae,pq_ag;

    localparam real    CLK_PERIOD = 42.0;   // 23.809524 MHz，与工作副本顶层一致
    // 工作副本顶层是 .CLK_DIV(23809524 / 100000 - 1)：两个整数字面量相除得 238，
    // 再减 1 == 237（不是 238）。uii2c 里 SCL_DIV = CLK_DIV/2 = 118，
    // scl_clk 周期 = 2*(118+1) = 238 拍父钟 = 9996 ns ≈ 100.04 kHz。
    // 这里必须用同一个数，否则 TB 跑的不是位流那个分频。
    localparam integer CLK_DIV    = 237;
    localparam integer SCL_CLKS   = 238;    // 一个 SCL 周期 = 238 拍父钟
    localparam [7:0]  CAM_W       = 8'h6c;  // 7 位从机地址 0x36 的写字节
    localparam [7:0]  CAM_R       = 8'h6d;  // 对应读字节

    reg         clk = 0;
    reg         rst_n = 0;
    reg         ae_req = 0;
    reg  [15:0] ae_val = 16'h0123;
    reg  [15:0] ag_val = 16'h0010;

    wire scl;
    tri1 sda;                               // 上拉：uii2c 的高电平靠释放总线
    wire cfg_done, ae_done, sensor_id_ok, iic_error, cfg_ok;
    wire [15:0] sensor_id;

    integer errors = 0, checks = 0;
    reg     test_done = 0;

    // ---- 从机激励开关 ----
    reg [15:0] slave_id  = 16'hee4b;
    reg        nack_addr = 0;               // 地址字节不 ACK
    reg        nack_data = 0;               // 数据字节（第 4 字节）不 ACK
    reg        no_slave  = 0;               // 完全没有摄像头

    // ---- 观测计数 ----
    integer wr_txn = 0, rd_txn = 0;
    integer n_start = 0, n_addr_seen = 0;
    reg [7:0] cur_ah = 8'hff, cur_al = 8'hff;
    reg [7:0] rd_hi_seen = 8'hff, rd_lo_seen = 8'hff;
    integer   n_wrong_addr = 0;

    // ---- 5 ms 等待测量 ----
    time    t_wait_enter = 0, t_wait_exit = 0;
    integer wait_cycles = 0;

    always #(CLK_PERIOD/2.0) if (!test_done) clk = ~clk;

    uicfgcs520 #(.CLK_DIV(CLK_DIV)) dut (
        .I_clk         (clk),
        .I_rst_n       (rst_n),
        .I_ae_req      (PQ_TEST ? pq_req : ae_req),
        .I_ae          (PQ_TEST ? pq_ae : ae_val),
        .I_ag          (PQ_TEST ? pq_ag : ag_val),
        .O_cam_scl     (scl),
        .IO_cam_sda    (sda),
        .O_cfg_done    (cfg_done),
        .O_ae_cfg_done (ae_done),
        .O_sensor_id   (sensor_id),
        .O_sensor_id_ok(sensor_id_ok),
        .O_iic_error   (iic_error),
        .O_cfg_ok      (cfg_ok)
    );

    generate if(PQ_TEST) begin: pq
        pq_control_glue chain(.S_24m_clk(clk),.S_cam_i2c_ready(rst_n),
            .S_cam_cfg_done(cfg_done),.S_ae_cfg_done(ae_done),.S_ag_toggle(pq_ag_toggle),
            .S_manual_toggle(pq_manual_toggle),.S_ae_sum(pq_sum),.S_ae_toggle(pq_stats_toggle),
            .S_ae_req(pq_req),.S_ae_auto_valid(pq_auto),.S_ae(pq_ae),.S_ag(pq_ag));
    end endgenerate

    //==================================================================
    // 期望值镜像：直接复用同一份寄存器表源码，逐条比对总线上真实发出的字节
    //   注意这只验证「顺序与线上取值」，不验证表内容本身是否正确
    //   （表内容属官方资料核对，不在本 TB 范围）。
    //==================================================================
    reg [15:0] exp_ae_val=16'h0123, exp_ag_val=16'h0010;
    reg  [8:0]  exp_idx = 9'd0;
    wire [23:0] exp_init_data;
    wire [8:0]  exp_init_size;
    wire [23:0] exp_gain;
    wire [23:0] exp_ae_data;
    wire [8:0]  exp_ae_size;

    uics520reg_720p60 u_exp_init (
        .REG_INDEX(exp_idx), .REG_DATA(exp_init_data), .REG_SIZE(exp_init_size));

    SC520GainTbl u_exp_gain (.I_AG(exp_ag_val), .O(exp_gain));

    uics520regAE u_exp_ae (
        .REG_INDEX(exp_idx), .REG_DATA(exp_ae_data), .REG_SIZE(exp_ae_size),
        .I_AE(exp_ae_val), .I_AG(exp_gain));

    //==================================================================
    // 被动监控：不驱动总线，只在 SCL 上升沿重建字节流
    //   一个字节 = 8 个数据位 + 1 个 ACK 位 = 9 个上升沿；
    //   START（SCL 高时 SDA 下降）把序号清零。
    //   写事务的 4 个字节依次是 dev / addr_h / addr_l / data。
    //==================================================================
    wire mon_bit = (sda === 1'b0) ? 1'b0 : 1'b1;
    integer   mon_edge = 0;
    reg [7:0] mon_sh = 8'h00;
    reg [7:0] mon_h = 8'h00, mon_l = 8'h00;
    reg       mon_rd = 1'b0;
    integer   mon_wr_n = 0;
    reg [15:0] log_addr [0:255];
    reg [7:0]  log_data [0:255];

    always @(negedge sda) if (scl === 1'b1 && !test_done) mon_edge = 0;

    always @(posedge scl) if (!test_done) begin
        if ((mon_edge % 9) < 8)
            mon_sh = {mon_sh[6:0], mon_bit};
        else begin
            case (mon_edge / 9)
                0: mon_rd = mon_sh[0];
                1: mon_h  = mon_sh;
                2: mon_l  = mon_sh;
                3: if (!mon_rd) begin
                       if (mon_wr_n < 256) begin
                           log_addr[mon_wr_n] = {mon_h, mon_l};
                           log_data[mon_wr_n] = mon_sh;
                       end
                       mon_wr_n = mon_wr_n + 1;
                   end
                default: ;
            endcase
        end
        mon_edge = mon_edge + 1;
    end

    //==================================================================
    // 引脚级从机
    //   全部用 SCL/SDA 的**电平**轮询，而不是边沿标志：
    //     - 边沿标志一个父钟就消失，循环里重复读同一个标志会造成零时间死循环；
    //     - 电平窗口有 120 拍父钟宽，不可能漏采样。
    //   START 仍用边沿（SDA 在 SCL 高时下降），它在每个父钟都被重新求值，
    //   只要轮询条件里包含它就不会漏。
    //==================================================================
    reg  scl_d = 1'b1, sda_d = 1'b1;
    always @(posedge clk) begin
        scl_d <= scl;
        sda_d <= sda;
    end

    wire start_cond = (sda_d === 1'b1) && (sda === 1'b0) && (scl === 1'b1);
    wire bit_val    = (sda === 1'b0) ? 1'b0 : 1'b1;
    // 必须用 !== 而不是 !：ModelSim 在 t=0 的初始化 delta 里 rst_n 可能是 x，
    // 那样 `if (abort)` 与 `if (!abort)` 会同时为假，循环不消耗时间而死锁。
    wire abort      = (rst_n !== 1'b1);

    reg       sda_low = 0;
    reg [7:0] btmp;
    reg [7:0] byte_addr, tx_val;
    reg       got_start = 0;

    assign sda = (sda_low && !no_slave) ? 1'b0 : 1'bz;

    function [7:0] rd_data_for;
        input [7:0] lo;
        begin
            if (lo == 8'h07) begin rd_data_for = slave_id[15:8]; rd_hi_seen = slave_id[15:8]; end
            else if (lo == 8'h08) begin rd_data_for = slave_id[7:0]; rd_lo_seen = slave_id[7:0]; end
            else begin rd_data_for = 8'h00; n_wrong_addr = n_wrong_addr + 1; end
        end
    endfunction

    // 等 START（SCL 高时 SDA 下降）。start_cond 是组合信号，在同一个仿真时刻
    // 内保持为真，必须在识别后消耗掉一拍，否则会被反复识别成新事件
    // （这正是曾经出现的零时间死循环）。
    task automatic w_start;
        begin
            while (!start_cond && !abort) @(posedge clk);
            @(posedge clk);                 // 任何情况下都至少消耗一拍
        end
    endtask

    task automatic w_low;
        begin
            while (scl !== 1'b0 && !abort) @(posedge clk);
        end
    endtask

    task automatic w_high;
        begin
            while (scl !== 1'b1 && !abort) @(posedge clk);
        end
    endtask

    // 收一个字节。若在收到 8 位之前出现 START（重复起始），置 got_start 退出，
    // 这样「3 字节写 + 重复起始」和「4 字节写」由同一段代码处理。
    // 两个内层循环都监视 start_cond：重复起始的 SCL 会先于 SDA 拉高，
    // 只在「等 SCL 低」阶段监视才可能漏掉它。
    task automatic rx_byte;
        integer j;
        begin
            btmp      = 8'h00;
            got_start = 0;
            j = 7;
            while (j >= 0 && !abort && !got_start) begin
                while (scl !== 1'b0 && !start_cond && !abort) @(posedge clk);
                if (start_cond || abort) begin
                    got_start = start_cond;
                    if (start_cond) @(posedge clk);     // 消耗掉该 START
                end else begin
                    while (scl !== 1'b1 && !start_cond && !abort) @(posedge clk);
                    if (start_cond || abort) begin
                        got_start = start_cond;
                        if (start_cond) @(posedge clk); // 消耗掉该 START
                    end else begin
                        btmp[j] = bit_val;
                        j = j - 1;
                    end
                end
            end
        end
    endtask

    // ACK：先确保 SCL 在低电平再把 SDA 拉低，等一个完整高电平（主机采样），
    // 再在下降沿释放。w_low 对「已经在低电平」的情况不会多等一个周期。
    task automatic send_ack;
        begin
            w_low;
            if (!abort) begin
                sda_low = 1'b1;
                w_high;
                w_low;
                sda_low = 1'b0;
            end
        end
    endtask

    // 位 7 在 SCL 低电平期间建立，之后每个下降沿更新下一位；
    // 每位都要跨过「高 -> 低」一个完整周期，不能只看电平。
    task automatic tx_byte;
        input [7:0] b;
        integer j;
        begin
            w_low;
            sda_low = b[7] ? 1'b0 : 1'b1;
            j = 6;
            while (j >= 0 && !abort) begin
                w_high;
                w_low;
                if (!abort) begin
                    sda_low = b[j] ? 1'b0 : 1'b1;
                    j = j - 1;
                end
            end
            if (!abort) begin
                w_high;
                w_low;
                sda_low = 1'b0;
            end
        end
    endtask

    task automatic do_txn;                  // 处理一次 START 起的整个事务
        begin
            got_start   = 0;
            n_start     = n_start + 1;
            sda_low     = 1'b0;

            rx_byte;                        // 字节 1：从机地址 + R/W
            if (!abort && !got_start) begin
                byte_addr   = btmp;
                n_addr_seen = n_addr_seen + 1;

                if (!((byte_addr == CAM_W || byte_addr == CAM_R) && !nack_addr)) begin
                    sda_low = 1'b0;         // 地址 NACK：不驱动 SDA
                end else begin
                    send_ack;

                    if (byte_addr[0]) begin
                        //======== 读事务：回一个字节 ========
                        tx_val = rd_data_for(cur_al);
                        rd_txn = rd_txn + 1;
                        tx_byte(tx_val);
                    end else begin
                        //======== 写事务：addr_h / addr_l / 可选的第 4 字节 ========
                        rx_byte;
                        if (!abort && !got_start) begin cur_ah = btmp; send_ack; end

                        if (!abort && !got_start) begin
                            rx_byte;
                            if (!got_start && !abort) begin cur_al = btmp; send_ack; end
                        end

                        if (!abort && !got_start) begin
                            rx_byte;            // 4 字节写的第 4 个字节
                            if (!got_start && !abort && !nack_data) send_ack;
                        end

                        if (!abort) wr_txn = wr_txn + 1;
                    end
                end
            end
            sda_low = 1'b0;
        end
    endtask

    initial begin : slave
        sda_low   = 1'b0;
        got_start = 1'b0;
        @(posedge clk);                     // 等复位信号在 t=0 之后确定下来
        forever begin
            if (abort) begin
                sda_low   = 1'b0;
                got_start = 1'b0;
                @(posedge clk);
            end else begin
                if (!got_start) w_start;
                if (!abort) do_txn;
            end
        end
    end

    // 5 ms（首条软复位写之后的 ST_RESET_WAIT）实测拍数
    always @(posedge clk) begin
        if (dut.state == 4'd12) begin
            if (t_wait_enter == 0) t_wait_enter = $time;
        end else if (t_wait_enter != 0 && t_wait_exit == 0)
            t_wait_exit = $time;
    end

    // 契约检查：主机忙期间 wr_data / wr_cnt / rd_cnt / iic_mode 必须保持不变。
    // uii2c 的约定是「请求可以保持到 busy 拉高后撤销，但数据/计数/模式必须保持到
    // busy 拉低」；这里以 busy 拉高后的第一拍为基准逐拍比对。
    // 与 tb_i2c_caller.v 对 SC500 路径做的是同一项检查。
    reg        hold_active  = 0;
    reg [31:0] hold_wr_data = 32'd0;
    reg [7:0]  hold_wr_cnt  = 8'd0, hold_rd_cnt = 8'd0;
    reg        hold_mode    = 1'b0;
    integer    hold_cycles  = 0, hold_violations = 0;

    always @(posedge clk) begin
        if (dut.iic_busy === 1'b1) begin
            if (!hold_active) begin
                hold_active  <= 1'b1;
                hold_wr_data <= dut.wr_data;
                hold_wr_cnt  <= dut.wr_cnt;
                hold_rd_cnt  <= dut.rd_cnt;
                hold_mode    <= dut.iic_mode;
            end else begin
                hold_cycles <= hold_cycles + 1;
                if (dut.wr_data !== hold_wr_data || dut.wr_cnt !== hold_wr_cnt ||
                    dut.rd_cnt  !== hold_rd_cnt  || dut.iic_mode !== hold_mode)
                    hold_violations <= hold_violations + 1;
            end
        end else begin
            hold_active <= 1'b0;
        end
    end

    //==================================================================
    // 测试序列
    //==================================================================
    // 复位前先把总线放空。uicfgcs520 进入 ST_IDLE 后会连续发起 165 笔写，
    // 若在其事务中途拉低 rst_n 而又不等总线回稳，下一用例会从错位的相位开始。
    task automatic quiesce;
        integer wc;
        begin
            wc = 0;
            while (dut.iic_busy === 1'b1 && wc < 2000000) begin
                @(posedge clk); wc = wc + 1;
            end
            repeat (SCL_CLKS) @(posedge clk);
        end
    endtask

    task automatic start_case;
        input [15:0] id;
        begin
            quiesce;
            nack_addr = 1'b0; nack_data = 1'b0; no_slave = 1'b0;
            slave_id  = id;
            ae_req    = 1'b0;
            rst_n     = 1'b0;
            repeat (8) @(posedge clk);
            rst_n = 1'b1;
        end
    endtask

    // 失败用例的判据必须带上"确实发生了预期的失败"，否则 DUT 完全不动作
    // （什么都不置位）也会被读成 PASS。
    task automatic run_case;
        input [15:0]  id;
        input         expect_ok;
        input [255:0] nm;
        integer       wc;
        reg           timed_out;
        begin
            start_case(id);

            wc = 0;
            while (!sensor_id_ok && !iic_error && dut.state !== 4'd11 && wc < 1000000) begin
                @(posedge clk); wc = wc + 1;
            end
            timed_out = (wc >= 1000000);
            repeat (600) @(posedge clk);

            checks = checks + 1;
            // sensor_id 必须等于给从机的 id —— 非法 ID 用例也要先真的读到 id 再进 ERROR
            // 失败用例还要求 O_cfg_ok 不得抬起（方案 C 的诚实信号）
            if (sensor_id_ok !== expect_ok || timed_out || sensor_id !== id ||
                (!expect_ok && dut.state !== 4'd11) || (!expect_ok && cfg_ok === 1'b1)) begin
                errors = errors + 1;
                $display("FAIL %0s: sensor_id_ok=%b expected=%b sensor_id=%h expected_id=%h state=%0d iic_error=%b cfg_ok=%b timed_out=%b",
                         nm, sensor_id_ok, expect_ok, sensor_id, id, dut.state, iic_error, cfg_ok, timed_out);
                $display("     diag: n_start=%0d n_addr=%0d wr=%0d rd=%0d state=%0d cur_ah=%h cur_al=%h rd_hi=%h rd_lo=%h wrong_addr=%0d",
                         n_start, n_addr_seen, wr_txn, rd_txn, dut.state, cur_ah, cur_al,
                         rd_hi_seen, rd_lo_seen, n_wrong_addr);
            end else begin
                $display("PASS %0s: sensor_id=%h ok=%b state=%0d rd=%0d wr=%0d rd_hi=%h rd_lo=%h",
                         nm, sensor_id, sensor_id_ok, dut.state, rd_txn, wr_txn, rd_hi_seen, rd_lo_seen);
            end
        end
    endtask

    // mode: 1=地址不 ACK  2=数据字节不 ACK  3=无摄像头
    // check_id：地址 NACK / 无摄像头时 ID 读本身也不可能成功，必须同时为 0；
    //           数据 NACK 发生在初始化写阶段，ID 读已经正确完成。
    //
    // 方案 C 的判据（用户 2026-09-29 决定）：
    //   - O_cfg_ok 在任何失败场景下都不得为 1（诚实信号）；
    //   - 数据 NACK 时 O_cfg_done 仍必须为 1（厂商语义未变 → AE/AG 按键通路不受影响），
    //     这正是选择方案 C 而不是直接门控 cfg_done 的目的，所以要显式断言。
    task automatic run_fail_case;
        input [1:0]   mode;
        input         check_id;
        input [255:0] nm;
        integer       wc;
        reg           expect_met;
        begin
            start_case(16'hee4b);
            mon_edge = 0; mon_wr_n = 0;
            nack_addr = (mode == 2'd1);
            nack_data = (mode == 2'd2);
            no_slave  = (mode == 2'd3);

            wc = 0;
            if (mode == 2'd2) begin
                // 数据 NACK：整张初始化表仍会被走完，cfg_done 照厂商语义抬起。
                // 上限 2,500,000 拍（约 105 ms）留出余量但对超时仍敏感：
                // 实际约 1.53M 拍（ID 读 + 165 笔写 + 首条后 5 ms），
                // 若回归成"门控 cfg_done"的旧行为，会在本上限内报出 FAIL 而不是拖到脚本超时。
                while (cfg_done !== 1'b1 && wc < 2500000) begin
                    @(posedge clk); wc = wc + 1;
                end
                expect_met = (cfg_done === 1'b1) && (mon_wr_n == exp_init_size);
            end else begin
                while (!iic_error && !cfg_done && wc < 1500000) begin
                    @(posedge clk); wc = wc + 1;
                end
                // 地址 NACK / 无摄像头：必须真的产生总线错误并锁存，否则 DUT 不动作也算 PASS
                expect_met = (iic_error === 1'b1) && (cfg_done === 1'b0);
            end
            repeat (2000) @(posedge clk);

            checks = checks + 1;
            if (cfg_ok === 1'b1 || (check_id && sensor_id_ok === 1'b1) || !expect_met) begin
                errors = errors + 1;
                $display("FAIL %0s: sensor_id_ok=%b cfg_done=%b cfg_ok=%b iic_error=%b state=%0d writes=%0d expect_met=%b",
                         nm, sensor_id_ok, cfg_done, cfg_ok, iic_error, dut.state, mon_wr_n, expect_met);
            end else begin
                $display("PASS %0s: cfg_ok=0, no false success (sensor_id_ok=%b cfg_done=%b iic_error=%b state=%0d writes=%0d)",
                         nm, sensor_id_ok, cfg_done, iic_error, dut.state, mon_wr_n);
            end
            nack_addr = 1'b0; nack_data = 1'b0; no_slave = 1'b0;
        end
    endtask

    // S7：事务进行到一半时复位，验证 FSM 从头重启并最终正确读到 ID。
    // 复位前断言 busy 为高，确保真的是"事务中"而不是碰巧落在两次事务之间。
    task automatic run_mid_reset;
        integer wc;
        begin
            start_case(16'hee4b);

            wc = 0;
            while (dut.iic_busy !== 1'b1 && wc < 200000) begin
                @(posedge clk); wc = wc + 1;
            end
            repeat (30000) @(posedge clk);  // 约 1.26 ms，仍在事务中
            checks = checks + 1;
            if (dut.iic_busy !== 1'b1) begin
                errors = errors + 1;
                $display("FAIL S7_mid_txn_reset: bus not busy when reset was asserted");
            end else
                $display("PASS S7_mid_txn_reset: reset asserted while iic_busy=1");
            rst_n = 1'b0;
            repeat (500) @(posedge clk);
            rst_n = 1'b1;

            wc = 0;
            while (!sensor_id_ok && !iic_error && wc < 1000000) begin
                @(posedge clk); wc = wc + 1;
            end
            repeat (600) @(posedge clk);

            checks = checks + 1;
            if (sensor_id_ok === 1'b1 && sensor_id === 16'hee4b)
                $display("PASS S7_mid_txn_reset: clean restart, sensor_id=%h", sensor_id);
            else begin
                errors = errors + 1;
                $display("FAIL S7_mid_txn_reset: sensor_id_ok=%b sensor_id=%h iic_error=%b state=%0d",
                         sensor_id_ok, sensor_id, iic_error, dut.state);
            end
        end
    endtask

    // S8：完整序列（165 条初始化 + 5 ms 等待 + 8 条 AE）
    task automatic run_full;
        integer i, n_init, n_ae, bad;
        integer wc;
        reg [15:0] ea;
        reg [7:0]  ed;
        begin
            start_case(16'hee4b);
            mon_edge = 0; mon_wr_n = 0;
            t_wait_enter = 0; t_wait_exit = 0;

            wc = 0;
            while (!cfg_done && !iic_error && wc < 8000000) begin
                @(posedge clk); wc = wc + 1;
            end
            n_init = mon_wr_n;

            exp_ae_val=ae_val; exp_ag_val=ag_val;
            ae_req = 1'b1;
            repeat (8) @(posedge clk);
            ae_req = 1'b0;
            while(mon_wr_n<n_init+2 && !iic_error) @(negedge clk);
            ae_val=16'h0456; ag_val=16'h0090;
            wc = 0;
            while (mon_wr_n < n_init + 8 && !iic_error && wc < 2000000) begin
                @(posedge clk); wc = wc + 1;
            end
            // Change the external source during an in-flight table walk.
            // The reference remains the accepted snapshot for all eight writes.
            // AE 表 8 条写完后 FSM 还要走完最后一笔事务才会抬 ae_cfg_done
            while (ae_done !== 1'b1 && !iic_error && wc < 4000000) begin
                @(posedge clk); wc = wc + 1;
            end
            repeat (400) @(posedge clk);
            n_ae = mon_wr_n - n_init;

            // ---- 完成标志（方案 C：cfg_done 厂商语义 + cfg_ok 诚实信号，正常路径两者都为 1）----
            checks = checks + 1;
            if (cfg_done === 1'b1 && ae_done === 1'b1 && iic_error === 1'b0 && cfg_ok === 1'b1)
                $display("PASS S8_flags: cfg_done=1 ae_cfg_done=1 iic_error=0 cfg_ok=1");
            else begin
                errors = errors + 1;
                $display("FAIL S8_flags: cfg_done=%b ae_cfg_done=%b iic_error=%b cfg_ok=%b",
                         cfg_done, ae_done, iic_error, cfg_ok);
            end

            // ---- 初始化表条数与逐条内容/顺序 ----
            checks = checks + 1;
            bad = 0;
            if (n_init !== exp_init_size) begin
                errors = errors + 1;
                $display("FAIL S8_init_count: %0d writes, expected %0d", n_init, exp_init_size);
            end else begin
                for (i = 0; i < n_init; i = i + 1) begin
                    exp_idx = i;
                    #1;
                    ea = exp_init_data[23:8];
                    ed = exp_init_data[7:0];
                    if (log_addr[i] !== ea || log_data[i] !== ed) begin
                        bad = bad + 1;
                        if (bad <= 5)
                            $display("   init[%0d] sent %h/%h expected %h/%h",
                                     i, log_addr[i], log_data[i], ea, ed);
                    end
                end
                if (bad != 0) begin
                    errors = errors + 1;
                    $display("FAIL S8_init_order: %0d/%0d entries differ from table", bad, n_init);
                end else
                    $display("PASS S8_init_order: %0d entries match table in order", n_init);
            end

            // ---- AE 表 ----
            checks = checks + 1;
            bad = 0;
            if (n_ae !== exp_ae_size) begin
                errors = errors + 1;
                $display("FAIL S8_ae_count: %0d writes, expected %0d", n_ae, exp_ae_size);
            end else begin
                for (i = 0; i < n_ae; i = i + 1) begin
                    exp_idx = i;
                    #1;
                    ea = exp_ae_data[23:8];
                    ed = exp_ae_data[7:0];
                    if (log_addr[n_init+i] !== ea || log_data[n_init+i] !== ed) begin
                        bad = bad + 1;
                        if (bad <= 5)
                            $display("   ae[%0d] sent %h/%h expected %h/%h",
                                     i, log_addr[n_init+i], log_data[n_init+i], ea, ed);
                    end
                end
                if (bad != 0) begin
                    errors = errors + 1;
                    $display("FAIL S8_ae_order: %0d/%0d entries differ from table", bad, n_ae);
                end else
                    $display("PASS S8_ae_order: %0d entries match table in order", n_ae);
            end

            // ---- 首条软复位写之后的 5 ms 等待（RESET_WAIT_CYCLES=119048 @23.809524MHz）----
            checks = checks + 1;
            if (t_wait_enter == 0 || t_wait_exit <= t_wait_enter) begin
                errors = errors + 1;
                $display("FAIL S8_reset_wait: ST_RESET_WAIT not observed");
            end else begin
                wait_cycles = (t_wait_exit - t_wait_enter) / 42;
                if (wait_cycles >= 119046 && wait_cycles <= 119050)
                    $display("PASS S8_reset_wait: %0d cycles (5.000 ms @23.809524MHz)", wait_cycles);
                else begin
                    errors = errors + 1;
                    $display("FAIL S8_reset_wait: %0d cycles, expected 119048", wait_cycles);
                end
            end

            // ---- ID 读仍然正确 ----
            checks = checks + 1;
            if (sensor_id === 16'hee4b && sensor_id_ok === 1'b1)
                $display("PASS S8_id: sensor_id=%h reads=%0d writes=%0d", sensor_id, rd_txn, wr_txn);
            else begin
                errors = errors + 1;
                $display("FAIL S8_id: sensor_id=%h ok=%b", sensor_id, sensor_id_ok);
            end
        end
    endtask

    task pq_check;
        input [255:0] tag; input cond;
        begin checks=checks+1;
            if(cond!==1'b1) begin errors=errors+1;
                $display("FAIL PQ %0s ae=%0d ag=%0d auto=%b writes=%0d",tag,pq_ae,pq_ag,pq_auto,mon_wr_n);end
        end
    endtask
    task pq_frame;
        input integer hi;
        begin @(negedge clk);pq_sum=hi<<12;pq_stats_toggle=~pq_stats_toggle;
            repeat(10) @(negedge clk);end
    endtask
    task pq_idle;
        integer wc,stable;
        begin wc=0;stable=0;
            while(stable<300 && wc<8000000) begin
                @(negedge clk);wc=wc+1;
                if(cfg_done && ae_done && !pq_req) stable=stable+1;else stable=0;
            end
            pq_check("idle reached",stable==300 && !iic_error);
        end
    endtask
    task run_pq;
        integer j,base,bad;
        reg [15:0] old_ae,old_ag;
        begin
            start_case(16'hee4b);pq_idle;
            pq_check("initialization low gain AUTO",pq_auto && pq_ae==1991 && pq_ag==16);
            base=mon_wr_n;
            for(j=0;j<12;j=j+1) pq_frame(28800);
            repeat(1000) @(negedge clk);
            pq_check("deadband sends no writes",mon_wr_n==base && !pq_req);
            for(j=0;j<4;j=j+1) pq_frame(40000);
            old_ae=pq_ae;old_ag=pq_ag;
            pq_check("changed auto transaction",old_ae==1975 && old_ag==16 && !ae_done);
            pq_manual_toggle=~pq_manual_toggle;
            for(j=0;j<8;j=j+1) pq_frame(40000);
            pq_check("busy ownership and values freeze",pq_auto && pq_ae==old_ae && pq_ag==old_ag);
            pq_idle;
            pq_check("short press MAN without jump",!pq_auto && pq_ae==old_ae && pq_ag==old_ag);
            exp_ae_val=old_ae;exp_ag_val=old_ag;bad=0;
            for(j=0;j<8;j=j+1) begin
                exp_idx=j;#1;
                if(log_addr[base+j]!==exp_ae_data[23:8] || log_data[base+j]!==exp_ae_data[7:0]) bad=bad+1;
            end
            pq_check("eight writes accepted snapshot",mon_wr_n==base+8 && bad==0);
            base=mon_wr_n;
            pq_ag_toggle[1]=~pq_ag_toggle[1];
            pq_idle;
            pq_check("one gain event increments from unity",!pq_auto && pq_ae==old_ae && pq_ag==old_ag+1 && mon_wr_n==base+8);
            base=mon_wr_n;old_ae=pq_ae;old_ag=pq_ag;
            repeat(10000) @(negedge clk);
            pq_check("held toggle sends no repeats",pq_ag==old_ag && mon_wr_n==base);
            // Start a transaction, then queue further steps while the sensor is busy.
            pq_ag_toggle[1]=~pq_ag_toggle[1];repeat(20) @(negedge clk);
            pq_check("gain transaction started",!ae_done && pq_ag==old_ag+1);
            pq_ag_toggle[1]=~pq_ag_toggle[1];repeat(20) @(negedge clk);
            pq_ag_toggle[1]=~pq_ag_toggle[1];repeat(20) @(negedge clk);
            pq_ag_toggle[0]=~pq_ag_toggle[0];repeat(20) @(negedge clk);
            pq_idle;
            pq_check("busy steps retained",pq_ag==old_ag+2 && pq_ae==old_ae);
            old_ae=pq_ae;old_ag=pq_ag;
            for(j=0;j<299;j=j+1) pq_frame(28800);
            pq_check("299 frames still MAN",!pq_auto);
            pq_frame(28800);
            pq_check("rearm from effective values",pq_auto && pq_ae==old_ae && pq_ag==old_ag);
            pq_idle;
        end
    endtask

    initial begin
        $display("=== tb_sc520_config: SC520 config sequence check ===");

        if(PQ_TEST) run_pq;
        else begin
        run_case(16'hee4b, 1'b1, "S1_valid_id_ee4b");
        run_case(16'h9e4b, 1'b1, "S2_valid_id_9e4b");
        run_case(16'h1234, 1'b0, "S3_invalid_id_1234");

        run_fail_case(2'd1, 1'b1, "S4_addr_nack");
        run_fail_case(2'd3, 1'b1, "S5_no_camera");
        run_fail_case(2'd2, 1'b0, "S6_data_nack");

        run_mid_reset;                  // S7
        run_full;                       // S8

        end

        // 读事务只允许访问 0x3107 / 0x3108（低字节 07/08）
        checks = checks + 1;
        if (n_wrong_addr != 0) begin
            errors = errors + 1;
            $display("FAIL read address: %0d reads used a low byte other than 0x07/0x08", n_wrong_addr);
        end else begin
            $display("PASS read address: all reads used 0x3107/0x3108 (%0d read transactions)", rd_txn);
        end

        // busy 期间输入必须稳定（uii2c 的数据/计数/模式契约）
        checks = checks + 1;
        if (hold_violations != 0) begin
            errors = errors + 1;
            $display("FAIL cmd_hold: %0d violations over %0d busy cycles",
                     hold_violations, hold_cycles);
        end else begin
            $display("PASS cmd_hold: 0 violations over %0d busy cycles", hold_cycles);
        end

        test_done = 1;
        if(errors==0 && PQ_TEST) $display("PASS pq_control checks=%0d errors=0",checks);
        else if (errors == 0) $display("PASS sc520_config checks=%0d errors=0", checks);
        else             $display("FAIL sc520_config checks=%0d errors=%0d", checks, errors);
        $finish;
    end

endmodule
