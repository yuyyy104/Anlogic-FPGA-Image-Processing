//======================================================================
// tb_i2c_randomread.v —— uii2c 随机读路径最小用例（P1 关键判别）
//
// 目的：判别「3 字节写 + 重复起始 + 1 字节读」在 uii2c 上到底能否完成。
//       这是 SC520 读 sensor ID（0x3107/0x3108）所必需的形态，
//       而此前所有测试只覆盖过「4 字节写」。
//
// 从机写法直接沿用已由 12 笔事务验证的 tb_i2c_reset.v：
//   @(posedge scl) 采样、@(negedge scl) 驱动 ACK。
//
// 配置：WMEN_LEN=4、RMEN_LEN=1、CLK_DIV=237（与 SC520 顶层一致；顶层写的是
//       .CLK_DIV(23809524 / 100000 - 1)，两个整数字面量相除得 238 再减 1 = 237）
//       I_wr_cnt=3、I_rd_cnt=1、I_iic_mode=1
//
// 期望：从机回 ACK -> 3 字节写完成 -> 重复起始 -> 地址|1 -> 读 1 字节
//       -> 主机 NACK -> STOP；O_rd_data 等于从机给出的字节。
//======================================================================
`timescale 1ns/1ps
module tb_i2c_randomread;

    reg        clk = 0, rst_n = 0, req = 0, slave_low = 0;
    wire       scl, busy, bus_error;
    tri1       sda;
    wire [7:0] rd_data;
    reg [31:0] wr_data = 32'h0007_316c;   // 字节 0/1/2 = dev(0x6c) / addr_h(0x31) / addr_l(0x07)

    reg        test_done = 0;
    integer    errors = 0;
    integer    n_scl_rise = 0, n_start = 0, n_byte = 0;

    // 从机要返回的字节（读 sensor ID 高字节的仿真值）
    reg [7:0]  slave_byte = 8'hEE;

    always #21 clk = ~clk;                 // 父钟 23.809524 MHz（42 ns）

    assign sda = slave_low ? 1'b0 : 1'bz;

    uii2c #(.WMEN_LEN(4), .RMEN_LEN(1), .CLK_DIV(237)) dut (
        .I_clk          (clk),
        .I_rstn         (rst_n),
        .O_iic_scl      (scl),
        .IO_iic_sda     (sda),
        .I_wr_data      (wr_data),
        .I_wr_cnt       (8'd3),
        .O_rd_data      (rd_data),
        .I_rd_cnt       (8'd1),
        .I_iic_req      (req),
        .I_iic_mode     (1'b1),
        .O_iic_busy     (busy),
        .O_iic_bus_error(bus_error),
        .IO_iic_sda_dg  ()
    );

    always @(posedge scl) if (!test_done) n_scl_rise = n_scl_rise + 1;

    // ---------------- 从机：沿用 tb_i2c_reset.v 的写法 ----------------
    // 3 字节写 + 重复起始 + 读 1 字节；读阶段由从机驱动数据位
    integer   k, jj;
    reg [7:0] rx;
    reg [7:0] addr_h, addr_l;
    reg [7:0] tx;

    initial begin : slave
        wait (rst_n == 1'b1);
        forever begin
            // ---- START / 重复起始 ----
            @(negedge sda);
            if (scl === 1'b1) begin
                n_start = n_start + 1;
                slave_low = 0;
                // 字节 1：地址 + R/W
                rx = 8'h00;
                for (k = 7; k >= 0; k = k - 1) begin
                    @(posedge scl);
                    rx[k] = sda;
                end
                @(negedge scl);
                slave_low = 1;                 // 地址 ACK
                @(posedge scl);
                @(negedge scl);
                slave_low = 0;

                if (rx[0] === 1'b1) begin
                    //======== 读：从机输出 1 字节 ========
                    tx = slave_byte;
                    slave_low = tx[7] ? 1'b0 : 1'b1;
                    for (k = 6; k >= 0; k = k - 1) begin
                        @(negedge scl);
                        slave_low = tx[k] ? 1'b0 : 1'b1;
                    end
                    @(negedge scl);
                    slave_low = 0;
                end else begin
                    //======== 写：收 2 字节（addr_h, addr_l）========
                    for (k = 1; k >= 0; k = k - 1) begin
                        rx = 8'h00;
                        for (jj = 7; jj >= 0; jj = jj - 1) begin
                            @(posedge scl);
                            rx[jj] = sda;
                        end
                        @(negedge scl);
                        slave_low = 1;
                        @(posedge scl);
                        @(negedge scl);
                        slave_low = 0;
                        if (k == 1) addr_h = rx; else addr_l = rx;
                        n_byte = n_byte + 1;
                    end
                end
            end
        end
    end

    // ---------------- 激励 ----------------
    initial begin
        // wr_data 期望顺序：由 uii2c 按 sda_r <= wr_data[(wcnt*8)+:8] 逐字节发送
        // 因此 byte0=dev, byte1=addr_h, byte2=addr_l
        wr_data = {8'h00, 8'h07, 8'h31, 8'h6c};
        repeat (5) @(negedge clk);
        rst_n = 1;
        repeat (5) @(negedge clk);
        @(negedge clk); #1; req = 1;
        @(posedge busy);
        @(negedge clk); #1; req = 0;

        // 等待事务结束：轮询 busy 下降，带超时（不用 fork/join_any）
        begin : wait_done
            integer wc;
            wc = 0;
            while (busy === 1'b1 && wc < 200000) begin
                @(posedge clk);
                wc = wc + 1;
            end
            if (busy === 1'b1) begin
                $display("FAIL randomread: timeout waiting busy low");
                errors = errors + 1;
            end
        end

        repeat (200) @(posedge clk);
        test_done = 1;

        $display("randomread result: rd_data=%h busy=%b bus_error=%b", rd_data, busy, bus_error);
        $display("randomread stats : n_scl_rise=%0d n_start=%0d wr_bytes=%0d",
                 n_scl_rise, n_start, n_byte);
        if (rd_data === slave_byte && bus_error === 1'b0 && n_scl_rise >= 27)
            $display("PASS i2c_randomread rd_data=%h (SCL edges=%0d)", rd_data, n_scl_rise);
        else begin
            errors = errors + 1;
            $display("FAIL i2c_randomread rd_data=%h expected=%h bus_error=%b SCL edges=%0d",
                     rd_data, slave_byte, bus_error, n_scl_rise);
        end
        if (errors == 0) $display("PASS i2c_randomread errors=0");
        else             $display("FAIL i2c_randomread errors=%0d", errors);
        $finish;
    end

endmodule
