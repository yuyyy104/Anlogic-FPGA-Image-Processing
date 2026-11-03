`timescale 1ns/1ps
// P4 stage 2a: binary morphology (open = erode then dilate) on the motion mask.
//
// Storage is BYTE wide (8 cells per word) rather than one bit per word: a 1-bit-wide
// 14400-deep array is not mapped to ERAM by this toolchain and cost ~5.9k distributed
// RAM LUTs on top of a slice overrun, while an 8-bit-wide array maps to ERAM like the
// frame store does. One byte therefore holds 8 consecutive cells of a row, bit k =
// cell 8g+k, and the pipeline works one group of 8 cells per beat.
//
// Structure: the raw mask is captured group by group into a ping-pong byte RAM, then
// two slow single-pass FSMs run while the *next* frame is being captured:
//
//   pass 1 (erode) : raw bank  -> erode RAM
//   pass 2 (dilate): erode RAM -> opened mask streamed out, one byte (8 cells) per beat
//
// For a group the FSM reads rows y, y-1 and y-2 at the same group column; a causal 3x3
// window then needs, per row, the previous 2 cells, which are taken from the previous
// group's byte. Rows outside the grid count as 0.
//
// CAUSAL 3x3 window: the result for cell (x,y) uses columns x-2..x and rows y-2..y. A
// centred window would need column x+1 and row y+1, which the raster stream does not
// have; P3 uses the same causal convention for its 3-tap horizontal window. Documented
// consequence: the opened mask is shifted +2 in both axes and shrinks by up to 2 cells,
// so the region stage compensates all four bbox edges by -2 cells. At the
// right/bottom grid boundary the shifted mask is clipped, not extrapolated.
module motion_mask #(
    parameter integer GRID_W = 160,
    parameter integer GRID_H = 90
)(
    input  wire        clk,
    input  wire        rst_n,
    // -------- capture side: raw mask bits in raster order --------
    input  wire        cell_ce,
    input  wire        frame_start,     // first cell of a frame
    input  wire        row_end,         // last cell of a row (x = GRID_W-1)
    input  wire        mv_bit,
    input  wire        frame_history,
    // -------- processed side: opened mask, one byte per beat --------
    output reg         out_ce,
    output reg  [7:0]  out_byte,        // bit k = cell (out_x0 + k)
    output reg  [7:0]  out_x0,          // first column of the group
    output reg  [7:0]  out_y,
    output reg         out_frame_start,
    output reg         out_frame_end,
    // -------- status --------
    output reg         proc_overflow,   // sticky overload; reset required
    output reg  [15:0] out_cells,       // opened cells streamed for the last frame
    output reg  [1:0]  state_dbg,       // 0 idle, 1 erode pass, 2 dilate pass
    output reg         out_frame_valid,
    output reg         out_global_change
);
    localparam integer GRP_W = GRID_W / 8;            // bytes per row (20)
    localparam integer GRP   = GRP_W * GRID_H;        // bytes per frame (1800)
    localparam integer AW    = 11;                    // ceil(log2(1800))
    localparam integer AW2   = AW + 1;
    localparam [AW-1:0]  GRP_M1 = GRP - 1;
    localparam [AW2-1:0] BANK_OFF = GRP;
    localparam [AW-1:0]  GRPW_A = GRP_W;
    localparam [7:0]     GW_M1 = GRID_W - 1;
    localparam [7:0]     GW_M8 = GRID_W - 8;

    reg [7:0] raw_mem [0:(2*GRP)-1] /* fehdl force_ram=1, ram_style="bram_fast" */;
    reg [7:0] ero_mem [0:GRP-1]     /* fehdl force_ram=1, ram_style="bram_fast" */;

    // ---------------- capture side ----------------
    reg        cap_bank;
    reg [2:0]  cap_i;                  // cell index inside the current group
    reg [7:0]  cap_byte;
    reg        cap_flush;              // the group byte is complete next cycle
    reg [AW-1:0] cap_g;
    reg [7:0]  cap_row;
    reg [AW2-1:0] cap_waddr;
    reg cap_active, cap_history;
    reg [15:0] cap_cells, cap_moves;
    reg proc_valid, proc_global;
    wire cap_accept = cell_ce && (cap_active || frame_start);
    reg proc_bank, proc_req;
    localparam [1:0] S_IDLE = 2'd0, S_ERODE = 2'd1, S_DILATE = 2'd2;
    reg [1:0] state;

    wire cap_frame_last = row_end && (cap_row == GRID_H[7:0] - 8'd1);
    wire [AW2-1:0] cap_gaddr = (cap_bank ? BANK_OFF : {AW2{1'b0}}) + cap_g;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cap_bank <= 1'b0; cap_i <= 3'd0; cap_byte <= 8'd0;
            cap_flush <= 1'b0; cap_g <= {AW{1'b0}}; cap_row <= 8'd0;
            cap_waddr <= {AW2{1'b0}};
            cap_active<=0; cap_history<=0; cap_cells<=0; cap_moves<=0;
        end else begin
            if (cap_flush) begin
                cap_flush <= 1'b0;
                cap_g     <= (cap_g == GRP_M1) ? {AW{1'b0}} : cap_g + 1'b1;
                if (cap_g == GRP_M1) cap_bank <= ~cap_bank;
            end
            if (cap_accept) begin
                if (frame_start) begin
                    cap_active<=1; cap_i<=1; cap_byte<={7'd0,mv_bit};
                    cap_g<=0; cap_row<=0; cap_cells<=1; cap_moves<=mv_bit;
                    cap_history<=frame_history;
                end else begin
                cap_cells<=cap_cells+16'd1;
                cap_moves<=cap_moves+{15'd0,mv_bit};
                cap_byte[cap_i] <= mv_bit;      // bit k = cell 8g+k
                if (cap_i == 3'd7) begin
                    cap_i     <= 3'd0;
                    cap_flush <= 1'b1;
                    cap_waddr <= cap_gaddr;     // stable address for the flush write
                end else begin
                    cap_i <= cap_i + 3'd1;
                end
                if (row_end) cap_row <= cap_frame_last ? 8'd0 : cap_row + 8'd1;
                if (cap_frame_last) cap_active<=0;
                end
            end
        end
    end

    always @(posedge clk)
        if (cap_flush && !(state!=S_IDLE &&
                           ((cap_waddr>=BANK_OFF) == proc_bank))) raw_mem[cap_waddr] <= cap_byte;

    // ---------------- pass FSM ----------------
    reg [2:0] cyc;
    reg [AW-1:0] g;                    // group column
    reg [7:0]    fy;                   // row
    reg [7:0]    rb0, rb1, rb2;        // group bytes of rows y, y-1, y-2
    reg [7:0]    pb0, pb1, pb2;        // their previous-group bytes (column history)

    wire [15:0] w0 = {rb0, pb0};   // high byte = current group, low byte = previous group
    wire [15:0] w1 = {rb1, pb1};
    wire [15:0] w2 = {rb2, pb2};

    // causal 3x3 reduction for the eight cells of the group
    reg [7:0] red_byte;
    integer ii;
    always @(*) begin
        red_byte = 8'd0;
        for (ii = 0; ii < 8; ii = ii + 1) begin
            if (state == S_DILATE)
                red_byte[ii] = |{w2[6+ii], w2[7+ii], w2[8+ii],
                                 w1[6+ii], w1[7+ii], w1[8+ii],
                                 w0[6+ii], w0[7+ii], w0[8+ii]};
            else
                red_byte[ii] = &{w2[6+ii], w2[7+ii], w2[8+ii],
                                 w1[6+ii], w1[7+ii], w1[8+ii],
                                 w0[6+ii], w0[7+ii], w0[8+ii]};
        end
    end

    // Row base addresses are kept as running counters (base0 = y*GRP_W, base1 = (y-1)*GRP_W,
    // base2 = (y-2)*GRP_W) instead of computing fy*GRP_W: the constant multiply made the tool
    // infer three DSPs for pure address arithmetic, which P4/P5 need for real signal maths.
    reg [AW-1:0] base0, base1, base2;
    wire [AW-1:0] a_cur = base0 + g;
    wire [AW-1:0] a_py  = (fy == 8'd0) ? {AW{1'b0}} : (base1 + g);
    wire [AW-1:0] a_py2 = (fy < 8'd2)   ? {AW{1'b0}} : (base2 + g);

    reg        rd_en, rd_ero;
    reg [AW2-1:0] raddr;
    always @(*) begin
        rd_en  = 1'b0;
        rd_ero = (state == S_DILATE);
        raddr  = {AW2{1'b0}};
        case (state)
        S_ERODE: case (cyc)
            3'd0: begin rd_en = 1'b1; raddr = (proc_bank ? BANK_OFF : {AW2{1'b0}}) + a_cur; end
            3'd2: begin rd_en = (fy != 8'd0); raddr = (proc_bank ? BANK_OFF : {AW2{1'b0}}) + a_py; end
            3'd4: begin rd_en = (fy >= 8'd2); raddr = (proc_bank ? BANK_OFF : {AW2{1'b0}}) + a_py2; end
            default: ;
        endcase
        S_DILATE: case (cyc)
            3'd0: begin rd_en = 1'b1; raddr = a_cur; end
            3'd2: begin rd_en = (fy != 8'd0); raddr = a_py; end
            3'd4: begin rd_en = (fy >= 8'd2); raddr = a_py2; end
            default: ;
        endcase
        default: ;
        endcase
    end

    // Each array gets its own registered read data before any selection happens: with a
    // shared read-data register the tool declined to map both arrays to block RAM and put
    // them in distributed RAM (u_mask: dram lut 768, eram 0, #eram stayed 53). The reads
    // must also stay unconditional - gating them with rd_en makes the tool fall back to
    // distributed RAM again, so "row outside the grid" is handled where the value is
    // latched in the FSM, not here.
    reg [7:0] rdat_raw, rdat_ero;
    always @(posedge clk) begin
        rdat_raw <= raw_mem[raddr];
        rdat_ero <= ero_mem[raddr[AW-1:0]];
    end
    wire [7:0] rdat = rd_ero ? rdat_ero : rdat_raw;

    wire group_last = (g == GRPW_A - 1'b1);
    wire row_last   = (fy == GRID_H[7:0] - 8'd1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; cyc <= 3'd0; g <= {AW{1'b0}}; fy <= 8'd0;
            base0 <= {AW{1'b0}}; base1 <= {AW{1'b0}}; base2 <= {AW{1'b0}};
            rb0 <= 8'd0; rb1 <= 8'd0; rb2 <= 8'd0;
            pb0 <= 8'd0; pb1 <= 8'd0; pb2 <= 8'd0;
            out_ce <= 1'b0; out_byte <= 8'd0; out_x0 <= 8'd0; out_y <= 8'd0;
            out_frame_start <= 1'b0; out_frame_end <= 1'b0;
            out_cells <= 16'd0; state_dbg <= 2'd0;
            proc_bank <= 1'b0; proc_req <= 1'b0; proc_overflow <= 1'b0;
            proc_valid<=0; proc_global<=0; out_frame_valid<=0; out_global_change<=0;
        end else begin
            out_ce <= 1'b0;
            out_frame_start <= 1'b0;
            out_frame_end <= 1'b0;
            state_dbg <= (state == S_ERODE) ? 2'd1 : (state == S_DILATE) ? 2'd2 : 2'd0;

            case (state)
            S_IDLE: begin
                cyc <= 3'd0; g <= {AW{1'b0}}; fy <= 8'd0;
                base0 <= {AW{1'b0}}; base1 <= {AW{1'b0}}; base2 <= {AW{1'b0}};
                rb0 <= 8'd0; rb1 <= 8'd0; rb2 <= 8'd0;
                pb0 <= 8'd0; pb1 <= 8'd0; pb2 <= 8'd0;
                if (proc_req) begin
                    proc_req <= 1'b0;
                    out_frame_valid<=proc_valid;
                    out_global_change<=proc_global;
                    state <= S_ERODE;
                end
            end

            S_ERODE, S_DILATE: begin
                if (cyc == 3'd6) begin
                    cyc <= 3'd0;
                    if (state == S_ERODE) ero_mem[a_cur] <= red_byte;
                    else begin
                        out_ce    <= 1'b1;
                        out_byte  <= red_byte;
                        out_x0    <= {g[4:0], 3'b000};          // 8*g
                        out_y     <= fy;
                        out_frame_start <= (g == {AW{1'b0}}) && (fy == 8'd0);
                        out_cells <= out_cells + (red_byte[0] + red_byte[1] + red_byte[2] +
                                                  red_byte[3] + red_byte[4] + red_byte[5] +
                                                  red_byte[6] + red_byte[7]);
                    end
                    // advance: byte columns first, then rows
                    pb0 <= rb0; pb1 <= rb1; pb2 <= rb2;
                    if (group_last) begin
                        pb0 <= 8'd0; pb1 <= 8'd0; pb2 <= 8'd0;
                        g <= {AW{1'b0}};
                        if (row_last) begin
                            fy <= 8'd0;
                            base0 <= {AW{1'b0}}; base1 <= {AW{1'b0}}; base2 <= {AW{1'b0}};
                            if (state == S_ERODE) begin
                                out_cells <= 16'd0;             // cleared for dilate
                                state <= S_DILATE;
                            end else begin
                                out_frame_end <= 1'b1;
                                state <= S_IDLE;
                            end
                        end else begin
                            fy <= fy + 8'd1;
                            base0 <= base0 + GRPW_A;
                            base1 <= base0;
                            base2 <= base1;
                        end
                    end else begin
                        g <= g + 1'b1;
                    end
                end else begin
                    cyc <= cyc + 3'd1;
                    // Latch the read issued in the previous cycle. Rows outside the grid
                    // are forced to 0 here (the reads themselves stay unconditional so the
                    // tool keeps both arrays in block RAM).
                    if (cyc == 3'd1) rb0 <= rdat;
                    if (cyc == 3'd3) rb1 <= (fy != 8'd0) ? rdat : 8'd0;
                    if (cyc == 3'd5) rb2 <= (fy >= 8'd2) ? rdat : 8'd0;
                end
            end

            default: state <= S_IDLE;
            endcase

            // capture-frame completion hands the bank to the FSM; a frame finishing
            // while the FSM is busy is dropped and flagged so the region stage can
            // publish INVALID (cap_bank itself is driven only in the capture block)
            if (cap_flush && state!=S_IDLE &&
                ((cap_waddr>=BANK_OFF) == proc_bank)) proc_overflow<=1'b1;
            if (cap_accept && cap_frame_last && (cap_i == 3'd7)) begin
                if (state == S_IDLE && !proc_req) begin
                    proc_bank <= cap_bank;
                    proc_req  <= 1'b1;
                    // >=75% changing cells is a global-change heuristic, not an
                    // illumination classifier. Large moving targets are suppressed too.
                    proc_global <= cap_moves+{15'd0,mv_bit} >= (GRID_W*GRID_H*3+3)/4;
                    proc_valid <= cap_history && (cap_cells==GRID_W*GRID_H-1) &&
                        (cap_moves+{15'd0,mv_bit} < (GRID_W*GRID_H*3+3)/4);
                end else begin
                    proc_overflow <= 1'b1;
                end
            end
        end
    end
endmodule
