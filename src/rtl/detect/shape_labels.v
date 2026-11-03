`timescale 1ns/1ps
// Shared 4-pixel-grid geometric CCL; widened columns, no motion-window offset.
module shape_labels #(
    parameter integer A_MIN=9, MAXRUN=32, MAXLBL=63
)(
    input wire clk, rst_n,
    input wire run_valid,
    input wire [8:0] run_x0, run_x1,
    input wire [7:0] run_y,
    input wire run_row_end,
    output reg run_ack,
    input wire runs_overflow, scan_overflow, frame_end, frame_invalid, frame_global_change,
    output reg global_change,
    output reg result_done,
    output reg regions_valid,
    output reg [7:0] region_count,
    output reg regions_overflow,
    output reg [15:0] r0_area, r1_area, r2_area, r3_area,
    output reg [8:0] r0_xmin,r0_xmax,r1_xmin,r1_xmax,r2_xmin,r2_xmax,r3_xmin,r3_xmax,
    output reg [8:0] r0_seed_x,r1_seed_x,r2_seed_x,r3_seed_x,
    output reg [7:0] r0_seed_y,r1_seed_y,r2_seed_y,r3_seed_y,
    output reg [7:0] r0_ymin,r0_ymax,r1_ymin,r1_ymax,r2_ymin,r2_ymax,r3_ymin,r3_ymax
);
    // {area, xmin, xmax, ymin, ymax, last_row}; storage is never reset.
    reg [74:0] labels [0:MAXLBL] /* fehdl force_ram=1, ram_style="bram_fast" */;
    reg [23:0] prev_runs [0:MAXRUN-1] /* fehdl force_ram=1, ram_style="bram_fast" */;
    reg [23:0] curr_runs [0:MAXRUN-1] /* fehdl force_ram=1, ram_style="bram_fast" */;
    reg [63:0] used;
    reg [5:0] la, wa, ti;
    reg [74:0] ld, wd;
    reg we;
    reg [23:0] pd, cd;
    localparam IDLE=0, SCAN=1, PWAIT=2, PCHECK=3, LWAIT=4, LLOAD=5,
               MWAIT=6, MFOLD=7, FIX=8, FWAIT=9, FCHECK=10, UPDATE=11,
               APPEND=12, ACKWAIT=13, CLOSE=14, CWAIT=15, CCHECK=16,
               COPY=17, TWAIT=18, TCOPY=19, PUBLISH=20, ALLOC=21;
    reg [4:0] state;
    reg [6:0] pn, cn, si, fi, ci;
    reg [5:0] best, loser;
    reg [8:0] x0, x1;reg [7:0] y;
    reg [74:0] survivor;
    reg [66:0] top0, top1, top2, top3;
    reg [15:0] count;
    reg bad, invalid_f, global_f, frame_pending, closing_frame;
    reg [5:0] free_lb, alloc_idx;
    wire prev_fix = state==FCHECK && fi<pn && pd[5:0]==loser;
    wire curr_fix = state==FCHECK && fi<cn && cd[5:0]==loser;
    wire prev_we = rst_n && (prev_fix || state==TCOPY);
    wire curr_we = rst_n && (curr_fix || (state==APPEND && cn<MAXRUN));
    wire [5:0] curr_wa = state==APPEND ? cn : fi;
    wire [23:0] prev_wd = state==TCOPY ? cd : {pd[23:6],best};
    wire [23:0] curr_wd = state==APPEND ? {x0,x1,best} : {cd[23:6],best};
    always @(posedge clk) begin
        ld <= labels[la];
        if (we) labels[wa] <= wd;
        if (prev_we) prev_runs[fi] <= prev_wd;
        if (curr_we) curr_runs[curr_wa] <= curr_wd;
        pd <= prev_runs[ti];
        cd <= curr_runs[ti];
    end
    function [74:0] union_record;
        input [74:0] a,b;
        begin
            union_record={((a[65:58]<b[65:58] || (a[65:58]==b[65:58] && a[74:66]<b[74:66]))?a[74:58]:b[74:58]),a[57:42]+b[57:42],
                (a[41:33]<b[41:33]?a[41:33]:b[41:33]),
                (a[32:24]>b[32:24]?a[32:24]:b[32:24]),
                (a[23:16]<b[23:16]?a[23:16]:b[23:16]),
                (a[15:8]>b[15:8]?a[15:8]:b[15:8]),a[7:0]};
        end
    endfunction
    function [66:0] compensated;
        input [66:0] a;begin compensated=a;end
    endfunction
    task retire;
        input [66:0] a;
        begin
            if (a[49:34]>=A_MIN) begin
                count<=count+16'd1;
                if (count==16'd255) bad<=1;
                if (a[49:34]>top0[49:34]) begin
                    top3<=top2; top2<=top1; top1<=top0; top0<=a;
                end else if (a[49:34]>top1[49:34]) begin
                    top3<=top2; top2<=top1; top1<=a;
                end else if (a[49:34]>top2[49:34]) begin
                    top3<=top2; top2<=a;
                end else if (a[49:34]>top3[49:34]) top3<=a;
            end
        end
    endtask
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=IDLE; used<=0; pn<=0; cn<=0; si<=0; fi<=0; ci<=0;
            la<=0; wa<=0; ti<=0; wd<=0; we<=0;
            best<=0; loser<=0; x0<=0; x1<=0; y<=0; survivor<=0;
            free_lb<=0; alloc_idx<=1;
            top0<=0; top1<=0; top2<=0; top3<=0; count<=0;
            bad<=0; invalid_f<=0; frame_pending<=0; closing_frame<=0;
            global_f<=0; global_change<=0;
            run_ack<=0; result_done<=0; regions_valid<=0;
            regions_overflow<=0; region_count<=0;
            {r0_seed_x,r0_seed_y,r0_area,r0_xmin,r0_xmax,r0_ymin,r0_ymax}<=0;
            {r1_seed_x,r1_seed_y,r1_area,r1_xmin,r1_xmax,r1_ymin,r1_ymax}<=0;
            {r2_seed_x,r2_seed_y,r2_area,r2_xmin,r2_xmax,r2_ymin,r2_ymax}<=0;
            {r3_seed_x,r3_seed_y,r3_area,r3_xmin,r3_xmax,r3_ymin,r3_ymax}<=0;
        end else begin
            we<=0; run_ack<=0; result_done<=0;
            if (runs_overflow || scan_overflow) bad<=1;
            if (frame_end) begin
                frame_pending<=1; invalid_f<=frame_invalid; global_f<=frame_global_change;
            end
            case(state)
            IDLE: begin
                if (frame_pending) begin
                    frame_pending<=0; closing_frame<=1; ci<=1; state<=CLOSE;
                end else if (run_row_end && !run_valid) begin
                    y<=run_y; closing_frame<=0; ci<=1; state<=CLOSE;
                end else if (run_valid) begin
                    x0<=run_x0; x1<=run_x1; y<=run_y;
                    best<=0; survivor<=0; si<=0; state<=SCAN;
                end
            end
            SCAN: begin
                if (si>=pn) begin
                    if (best==0) begin alloc_idx<=1; state<=ALLOC; end
                    else state<=UPDATE;
                end
                else begin ti<=si[5:0]; state<=PWAIT; end
            end
            // One bitmap lookup per cycle. A combinational 63-way priority
            // chain exceeded the pixel-clock budget; the run handshake allows
            // this bounded search without changing component semantics.
            ALLOC: begin
                if (!used[alloc_idx]) begin free_lb<=alloc_idx; state<=UPDATE; end
                else if (alloc_idx==MAXLBL) begin free_lb<=0; state<=UPDATE; end
                else alloc_idx<=alloc_idx+1'b1;
            end
            PWAIT: state<=PCHECK;
            PCHECK: begin
                if (({1'b0,x0}<={1'b0,pd[14:6]}+10'd1) &&
                    ({1'b0,pd[23:15]}<={1'b0,x1}+10'd1) && used[pd[5:0]]) begin
                    if (best==0) begin
                        best<=pd[5:0]; la<=pd[5:0]; state<=LWAIT;
                    end else if (pd[5:0]!=best) begin
                        loser<=pd[5:0]; la<=pd[5:0]; state<=MWAIT;
                    end else begin si<=si+1; state<=SCAN; end
                end else begin si<=si+1; state<=SCAN; end
            end
            LWAIT: state<=LLOAD;
            LLOAD: begin survivor<=ld; si<=si+1; state<=SCAN; end
            MWAIT: state<=MFOLD;
            MFOLD: begin
                survivor<=union_record(survivor,ld); used[loser]<=0;
                fi<=0; state<=FIX;
            end
            FIX: begin
                if (fi>=pn && fi>=cn) begin si<=si+1; state<=SCAN; end
                else begin ti<=fi[5:0]; state<=FWAIT; end
            end
            FWAIT: state<=FCHECK;
            FCHECK: begin
                fi<=fi+1; state<=FIX;
            end
            UPDATE: begin
                if (best==0) begin
                    if (free_lb==0) begin bad<=1; run_ack<=1; state<=ACKWAIT; end
                    else begin
                        best<=free_lb; used[free_lb]<=1;
                        wa<=free_lb; wd<={x0,y,(16'd1+{7'd0,x1}-{7'd0,x0}),x0,x1,y,y,y};
                        we<=1; state<=APPEND;
                    end
                end else begin
                    wa<=best;
                    wd<={survivor[74:58],survivor[57:42]+16'd1+{7'd0,x1}-{7'd0,x0},
                        (x0<survivor[41:33]?x0:survivor[41:33]),
                        (x1>survivor[32:24]?x1:survivor[32:24]),
                        survivor[23:16],y,y};
                    we<=1; state<=APPEND;
                end
            end
            APPEND: begin
                if (cn<MAXRUN) begin cn<=cn+1; end
                else bad<=1;
                run_ack<=1; state<=ACKWAIT;
            end
            ACKWAIT: if (!run_valid && !run_row_end) state<=IDLE;
            CLOSE: begin
                if (ci>MAXLBL) begin
                    if (closing_frame) state<=PUBLISH;
                    else begin fi<=0; state<=COPY; end
                end else if (used[ci]) begin la<=ci[5:0]; state<=CWAIT; end
                else ci<=ci+1;
            end
            CWAIT: state<=CCHECK;
            CCHECK: begin
                if (closing_frame || ld[7:0]!=y) begin
                    retire(ld[74:8]); used[ci]<=0;
                end
                ci<=ci+1; state<=CLOSE;
            end
            COPY: begin
                if (fi>=cn) begin pn<=cn; cn<=0; run_ack<=1; state<=ACKWAIT; end
                else begin ti<=fi[5:0]; state<=TWAIT; end
            end
            TWAIT: state<=TCOPY;
            TCOPY: begin fi<=fi+1; state<=COPY; end
            PUBLISH: begin
                global_change<=global_f;
                regions_valid<=!bad && !invalid_f && !runs_overflow && !scan_overflow;
                regions_overflow<=bad || runs_overflow || scan_overflow;
                region_count<=(bad || invalid_f || runs_overflow || scan_overflow)?8'd0:
                    (count>255?8'd255:count[7:0]);
                {r0_seed_x,r0_seed_y,r0_area,r0_xmin,r0_xmax,r0_ymin,r0_ymax}<=
                    (bad || invalid_f || runs_overflow || scan_overflow)?67'd0:compensated(top0);
                {r1_seed_x,r1_seed_y,r1_area,r1_xmin,r1_xmax,r1_ymin,r1_ymax}<=
                    (bad || invalid_f || runs_overflow || scan_overflow)?67'd0:compensated(top1);
                {r2_seed_x,r2_seed_y,r2_area,r2_xmin,r2_xmax,r2_ymin,r2_ymax}<=
                    (bad || invalid_f || runs_overflow || scan_overflow)?67'd0:compensated(top2);
                {r3_seed_x,r3_seed_y,r3_area,r3_xmin,r3_xmax,r3_ymin,r3_ymax}<=
                    (bad || invalid_f || runs_overflow || scan_overflow)?67'd0:compensated(top3);
                result_done<=1; pn<=0; cn<=0; used<=0;
                top0<=0; top1<=0; top2<=0; top3<=0; count<=0;
                bad<=0; invalid_f<=0; state<=IDLE;
            end
            default: state<=IDLE;
            endcase
        end
    end
endmodule
