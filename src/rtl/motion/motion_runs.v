`timescale 1ns/1ps
// P4 stage 3a: run extraction for the region counter.
//
// The opened mask arrives as one byte per beat (8 cells, bit k = cell x0+k) from
// motion_mask. This stage stores a whole mask frame in a ping-pong byte RAM and walks
// it in raster order, emitting one run per (x0,x1,row).
//
// The scan is flow controlled: a run stays on the outputs until the consumer asserts
// run_ack, so no FIFO is needed downstream. Position advance is explicit - one cell per
// cycle, groups inside a row, rows last - and a row is only left after all of its runs
// (including the row-end flush of a run still open at the last column) have been acked.
// run_row_end marks the last run of a row; a row with more than MAXRUN runs sets
// runs_overflow, which the label stage turns into INVALID for the whole frame (never a
// silently truncated count).
//
// Block-RAM notes (learned on motion_mask): the read is UNCONDITIONAL and registered,
// and the address must be stable for a full cycle before the data is latched (hence the
// separate S_WAIT state).
module motion_runs #(
    parameter integer GRID_W = 160,
    parameter integer GRID_H = 90,
    parameter integer MAXRUN = 32
)(
    input  wire        clk,
    input  wire        rst_n,
    // -------- opened-mask byte stream --------
    input  wire        in_ce,
    input  wire [7:0]  in_byte,
    input  wire [7:0]  in_x,             // first column of the group (8*g)
    input  wire [7:0]  in_y,
    input  wire        in_frame_start,
    input  wire        in_frame_invalid,
    input  wire        in_global_change,
    // -------- run stream (flow controlled) --------
    output wire        run_valid,
    output wire [7:0]  run_x0,
    output wire [7:0]  run_x1,
    output wire [7:0]  run_y,
    output wire        run_row_end,
    input  wire        run_ack,
    // -------- status --------
    output reg         runs_overflow,
    output reg  [15:0] run_count,
    output reg  [7:0]  runs_max_row,
    output reg         frame_done,       // one pulse after the last run was accepted
    output reg         scan_overflow,    // sticky overload: reset required
    output reg         frame_invalid, frame_global_change
);
    localparam integer GRP_W = GRID_W / 8;             // bytes per row (20)
    localparam integer GRP   = GRP_W * GRID_H;         // bytes per frame (1800)
    localparam integer AW    = 11;                     // ceil(log2(1800))
    localparam integer AW2   = AW + 1;
    localparam [AW-1:0]  GRP_M1 = GRP - 1;
    localparam [AW2-1:0] BANK_OFF = GRP;
    localparam [7:0]     GRPW_A   = GRP_W;
    localparam [7:0]     GH_M1    = GRID_H - 1;
    localparam [7:0]     GW_M8    = GRID_W - 8;

    reg [7:0] msk_mem [0:(2*GRP)-1] /* fehdl force_ram=1, ram_style="bram_fast" */;

    // ---------------- state (declared before the blocks that drive it) ----------------
    localparam [2:0] S_IDLE = 3'd0, S_RD = 3'd1, S_WAIT = 3'd2,
                     S_SAMPLE = 3'd3, S_EMIT = 3'd4, S_ROWEND = 3'd5, S_GAP = 3'd6;
    reg [2:0]  state;
    reg [7:0]  sy;
    reg [AW-1:0] sg;
    reg [2:0]  sbit;
    reg [7:0]  sbyte;
    reg        open_run;
    reg [7:0]  open_x0;
    reg [7:0]  row_runs;
    reg        pend_valid;
    reg [7:0]  pend_x0, pend_x1, pend_y;
    reg        pend_row_end;

    // ---------------- capture ----------------
    // The input is a BYTE stream (one byte per beat, 8 cells), so it is written straight
    // into the frame RAM; the byte index itself selects the banked address.
    reg [AW-1:0] cap_idx;
    reg          cap_bank;
    reg          cap_active, cap_invalid, cap_global, scan_bank;

    wire [AW2-1:0] cap_addr = (cap_bank ? BANK_OFF : {AW2{1'b0}}) +
                             (in_frame_start ? {AW{1'b0}} : cap_idx);
    wire cap_accept = in_ce && (cap_active || in_frame_start);
    wire cap_frame_last = cap_accept && (in_y == GH_M1) && (in_x == GW_M8);

    always @(posedge clk)
        if (cap_accept && (state == S_IDLE || cap_bank != scan_bank))
            msk_mem[cap_addr] <= in_byte;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cap_idx <= {AW{1'b0}};
            cap_bank <= 1'b0;
            cap_active <= 1'b0; cap_invalid <= 1'b0; cap_global <= 0;
        end else if (cap_accept) begin
            if (in_frame_start) begin
                cap_active <= 1'b1; cap_invalid <= in_frame_invalid;
                cap_global <= in_global_change;
            end
            cap_idx <= cap_frame_last ? {AW{1'b0}} :
                       (in_frame_start ? {{(AW-1){1'b0}},1'b1} : cap_idx + 1'b1);
            if (cap_frame_last) begin cap_bank <= ~cap_bank; cap_active <= 1'b0; end
        end
    end

    // scan_overflow is owned by this block; the scan itself starts directly from
    // cap_frame_last (no request/ack register: the completed bank is always ~cap_bank,
    // because cap_bank flips exactly at the frame's last beat and then stays put).
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) scan_overflow <= 1'b0;
        else if ((cap_frame_last && state != S_IDLE) ||
                 (cap_accept && state != S_IDLE && cap_bank == scan_bank)) scan_overflow <= 1'b1;
    end

    // ---------------- scan side ----------------
    // Row base is a running counter (0, GRP_W, 2*GRP_W, ...): computing sy*GRP_W here
    // would infer a multiplier for pure address arithmetic.
    reg [AW-1:0] sbase;
    reg [7:0] rdat;
    always @(posedge clk) begin
        rdat <= msk_mem[(scan_bank ? BANK_OFF : {AW2{1'b0}}) + sbase + sg];
    end

    wire at_row_end = (sbit == 3'd7) && (sg == (GRPW_A - 8'd1));   // never part-select a parameter
    wire cell_on    = sbyte[sbit];                       // 'cell' is a Verilog keyword
    wire [7:0] cell_col = {sg[4:0], 3'b000} + {5'd0, sbit};

    // A run closes when a 0 follows it, or at the row end: a 1 at the last column
    // extends the run to GRID_W-1, a 0 ends it at GRID_W-2.
    wire run_close   = (at_row_end && cell_on) ? 1'b1 : (!cell_on && open_run);
    wire [7:0] close_x0 = (at_row_end && cell_on && !open_run) ? cell_col : open_x0;
    wire [7:0] close_x1 = (at_row_end && cell_on) ? (GRID_W[7:0] - 8'd1) : (cell_col - 8'd1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; sy <= 8'd0; sg <= {AW{1'b0}}; sbit <= 3'd0; sbyte <= 8'd0;
            open_run <= 1'b0; open_x0 <= 8'd0; row_runs <= 8'd0;
            pend_valid <= 1'b0; pend_x0 <= 8'd0; pend_x1 <= 8'd0; pend_y <= 8'd0;
            pend_row_end <= 1'b0;
            runs_overflow <= 1'b0; run_count <= 16'd0;
            runs_max_row <= 8'd0; frame_done <= 1'b0;
            scan_bank <= 1'b0; frame_invalid <= 1'b0; frame_global_change <= 0; sbase <= 0;
        end else begin
            frame_done <= 1'b0;

            case (state)
            S_IDLE: begin
                sy <= 8'd0; sg <= {AW{1'b0}}; sbit <= 3'd0; sbase <= {AW{1'b0}};
                open_run <= 1'b0; row_runs <= 8'd0; pend_valid <= 1'b0;
                // the completed frame is in the bank that is no longer being captured
                if (cap_frame_last) begin
                    scan_bank <= cap_bank; frame_invalid <= cap_invalid;
                    frame_global_change <= cap_global;
                    runs_overflow <= 1'b0; runs_max_row <= 0; run_count <= 0;
                    state <= S_RD;
                end
            end

            S_RD:   state <= S_WAIT;          // sg is the address for this cycle

            S_WAIT: begin                     // the registered read lands here
                sbyte <= rdat;
                sbit  <= 3'd0;
                state <= S_SAMPLE;
            end

            S_SAMPLE: begin
                if (run_close) begin
                    pend_valid   <= 1'b1;
                    pend_x0      <= close_x0;
                    pend_x1      <= close_x1;
                    pend_y       <= sy;
                    pend_row_end <= at_row_end;
                    open_run     <= 1'b0;
                    state        <= S_EMIT;
                end else begin
                    if (cell_on && !open_run) begin
                        open_run <= 1'b1;
                        open_x0  <= cell_col;
                    end
                    if (at_row_end) begin
                        state <= S_ROWEND;
                    end else if (sbit == 3'd7) begin
                        // next group in the same row: go back through S_RD so its byte is
                        // actually read (without this every group reused the first byte)
                        sbit  <= 3'd0;
                        sg    <= sg + 1'b1;
                        state <= S_RD;
                    end else begin
                        sbit <= sbit + 3'd1;
                    end
                end
            end

            S_EMIT: begin
                if (run_ack) begin
                    pend_valid <= 1'b0;
                    run_count  <= run_count + 16'd1;
                    row_runs   <= row_runs + 8'd1;
                    // The zero that closed a run has already been consumed.
                    if (at_row_end) state <= S_GAP;
                    else if (sbit == 3'd7) begin sg <= sg + 1'b1; state <= S_RD; end
                    else begin sbit <= sbit + 3'd1; state <= S_SAMPLE; end
                end
            end

            S_GAP: state <= S_ROWEND;
            S_ROWEND: begin
                if (row_runs > MAXRUN) runs_overflow <= 1'b1;
                if (run_ack) begin
                    if (row_runs > runs_max_row) runs_max_row <= row_runs;
                    row_runs <= 8'd0; open_run <= 1'b0;
                    if (sy == GH_M1) begin frame_done <= 1'b1; state <= S_IDLE; end
                    else begin
                        sy <= sy + 8'd1; sg <= 0; sbit <= 0;
                        sbase <= sbase + GRPW_A; state <= S_RD;
                    end
                end
            end

            default: state <= S_IDLE;
            endcase
        end
    end
    // Outputs are combinational from the pending run: registering them as well put one
    // extra stage between run_valid and the data, which made every emitted run carry the
    // previous run's coordinates.
    assign run_valid   = (state == S_EMIT);
    assign run_x0      = pend_x0;
    assign run_x1      = pend_x1;
    assign run_y       = (state == S_ROWEND) ? sy : pend_y;
    // Every row, including empty rows, has a separate acknowledged boundary.
    assign run_row_end = (state == S_ROWEND);

endmodule
