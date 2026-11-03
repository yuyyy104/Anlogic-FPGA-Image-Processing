// P5: frame identity + acquisition-to-output latency bookkeeping.
//
// Everything here runs in the DDR/user clock domain (S_ddr_clk, ~133.333 MHz) - the same
// domain that owns the frame slots and the read base. A held payload plus a toggle carries each
// display measurement; validity may additionally fall to revoke a torn or underflowed frame.
//
// Measurement definition (do not widen silently):
//   t_in  = video_in's DDR-domain observation of ISP frame start
//   t_out = hdmi_mixer's registered RGB output first pixel, observed back in the DDR domain
// The transmitter/PHY after the mixer is outside this measurement.
// It excludes camera exposure, the CSI/ISP pipeline before the first output pixel, and any
// display-internal delay.
module frame_meta #(
    // (1280*720/16)*3 = 720 bursts * 240 beats. Derived from the vendor word packing, not yet
    // measured on hardware.
    parameter integer EXPECTED_BEATS = 172800,
    // Strict by default: never hide an incomplete frame by accepting a line-count offset.
    parameter integer BEAT_TOL       = 0,
    // DDR cycles per millisecond at 133.333 MHz. Relative error 2.5e-6 (~0.9 ms drift / 10 h).
    parameter integer MS_DIV         = 133333
)(
    input  wire        clk,             // S_ddr_clk
    input  wire        rst_n,

    input  wire        i_frame_start,   // video_in: S_frame_start, 1 ddr cycle
    input  wire [1:0]  i_wr_slot,       // video_in wp: meaningful as the new slot ONLY at frame start
    input  wire        i_wr_en,         // video_in: accepted DDR write beats
    input  wire        i_wr_busy,       // an unfinished burst at frame start taints the new frame
    input  wire [1:0]  i_rp,            // video_in: slot currently selected for display
    input  wire        i_vsync,         // display vsync (same net video_out samples)
    input  wire        i_out_tgl,       // pixel domain: toggles at the first output pixel
    input  wire        i_read_fault,    // pixel-domain sticky FIFO underflow, cleared at vsync
    input  wire        i_capture_fault, // camera-domain sticky input staging loss

    output reg  [15:0] o_lat_ms,        // measured latency, saturated at 999
    output reg         o_lat_valid,     // 0 => the pixel side must show INVALID
    output reg         o_pub_tgl,       // event bit to the pixel domain
    output reg  [1:0]  o_state,         // snapshot state (probe / TB)
    output reg  [23:0] o_frame_id,      // snapshot frame id (probe / TB)
    output reg         o_short,         // last completed frame had too few beats
    output reg         o_over           // last completed frame had too many beats
);

    localparam [1:0] ST_IDLE      = 2'd0;
    localparam [1:0] ST_OCCUPYING = 2'd1;
    localparam [1:0] ST_COMMITTED = 2'd2;
    localparam [1:0] ST_STALE     = 2'd3;

    localparam [17:0] EXP_LO = EXPECTED_BEATS - BEAT_TOL;
    localparam [17:0] EXP_HI = EXPECTED_BEATS + BEAT_TOL;

    // ---------------- millisecond time base ----------------
    localparam integer MS_CNT_W = (MS_DIV <= 1) ? 1 : $clog2(MS_DIV);
    reg [MS_CNT_W-1:0] ms_cnt;
    reg [31:0] r_ms;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            ms_cnt <= 32'd0;
            r_ms   <= 32'd0;
        end else if(ms_cnt >= (MS_DIV-1)) begin
            ms_cnt <= 32'd0;
            r_ms   <= r_ms + 32'd1;
        end else begin
            ms_cnt <= ms_cnt + 32'd1;
        end
    end

    // ---------------- slot table (4 slots, same mapping as video_in) ----------------
    reg [1:0]  st    [0:3];
    reg [7:0]  sgen  [0:3];
    reg [23:0] sfid  [0:3];
    reg [31:0] stin  [0:3];
    reg [17:0] sbeats[0:3];

    reg [23:0] wr_fid;
    reg [1:0] active_slot;
    reg active_seen, active_bad;
    // wp advances at frame start. Retain the pre-edge slot until the next frame start rather
    // than counting subsequent beats under the already-advanced pointer. A write on that next
    // start edge still addresses the OLD base and is part of the old frame's final count.
    wire [18:0] fin_beats = {1'b0,sbeats[active_slot]} + i_wr_en;
    wire fin_ok = !active_bad && (fin_beats >= EXP_LO) && (fin_beats <= EXP_HI);

    integer k;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            for(k=0;k<4;k=k+1) begin
                st[k]<=ST_IDLE; sgen[k]<=8'd0; sfid[k]<=24'd0; stin[k]<=32'd0; sbeats[k]<=18'd0;
            end
            wr_fid<=24'd0; o_short<=1'b0; o_over<=1'b0;
            active_slot<=0; active_seen<=0; active_bad<=0;
        end else begin
            if(i_wr_en && active_seen && !i_frame_start) begin
                if(sbeats[active_slot] != 18'h3ffff)
                    sbeats[active_slot] <= sbeats[active_slot] + 18'd1;
                else active_bad <= 1'b1;
            end

            if(i_frame_start) begin
                if(active_seen) begin
                    st[active_slot] <= fin_ok ? ST_COMMITTED : ST_STALE;
                    sbeats[active_slot] <= fin_beats[18] ? 18'h3ffff : fin_beats[17:0];
                    if(fin_ok) sgen[active_slot] <= sgen[active_slot] + 8'd1;
                    o_short <= (fin_beats < EXP_LO);
                    o_over <= active_bad || (fin_beats > EXP_HI);
                end
                active_slot <= i_wr_slot;
                active_seen <= 1'b1;
                // An unfinished old burst can put old pixels at the freshly reset new base.
                // Count its transactions for diagnostics but never certify the new frame.
                active_bad <= i_wr_busy;
                st[i_wr_slot]     <= ST_OCCUPYING;
                sfid[i_wr_slot]   <= wr_fid + 24'd1;
                stin[i_wr_slot]   <= r_ms;
                sbeats[i_wr_slot] <= 18'd0;
                wr_fid            <= wr_fid + 24'd1;
            end
        end
    end

    // ---------------- display-side snapshot (ddr domain, same cycle as video_out) --------
    // Replicates video_out's vsync 3FF + rising edge so the snapshot happens on exactly the
    // cycle video_out latches its read base from the same i_rp.
    reg vs1, vs2, vs3;
    wire disp_fs = ~vs3 & vs2;
    always @(posedge clk) begin
        vs1 <= i_vsync;
        vs2 <= vs1;
        vs3 <= vs2;
    end

    reg [1:0]  sn_state;
    reg [23:0] sn_fid;
    reg [7:0]  sn_gen;
    reg [31:0] sn_tin;
    reg [1:0]  sn_slot;
    reg sn_seen, sn_tainted;
    wire overwriting_snapshot = i_frame_start && (i_wr_slot == sn_slot);

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            sn_state<=ST_IDLE; sn_fid<=24'd0; sn_gen<=8'd0; sn_tin<=32'd0; sn_slot<=2'd0;
            sn_seen<=0; sn_tainted<=0;
        end else if(disp_fs) begin
            sn_state <= st[i_rp];
            sn_fid   <= sfid[i_rp];
            sn_gen   <= sgen[i_rp];
            sn_tin   <= stin[i_rp];
            sn_slot  <= i_rp;
            sn_seen <= 1'b1;
            sn_tainted <= i_frame_start && (i_wr_slot == i_rp);
        end else if(overwriting_snapshot) begin
            sn_tainted <= 1'b1;
        end
    end

    // ---------------- output-pixel event (pixel -> ddr) ----------------
    reg ot1, ot2, ot3, otd;
    reg uf1, uf2;
    reg cf1, cf2;
    wire out_evt = ot3 ^ otd;
    wire       snap_ok  = sn_seen && !sn_tainted && !overwriting_snapshot && !uf2 && !cf2 &&
                          (sn_state == ST_COMMITTED) &&
                          (st[sn_slot] == ST_COMMITTED) &&
                          (sgen[sn_slot] == sn_gen);
    wire [31:0] lat_diff = r_ms - sn_tin;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            ot1<=1'b0; ot2<=1'b0; ot3<=1'b0; otd<=1'b0;
            uf1<=0; uf2<=0;
            cf1<=0; cf2<=0;
            o_lat_ms<=16'd0; o_lat_valid<=1'b0; o_pub_tgl<=1'b0;
            o_state<=ST_IDLE; o_frame_id<=24'd0;
        end else begin
            ot1<=i_out_tgl; ot2<=ot1; ot3<=ot2; otd<=ot3;
            uf1<=i_read_fault; uf2<=uf1;
            cf1<=i_capture_fault; cf2<=cf1;

            o_state    <= sn_state;
            o_frame_id <= sn_fid;

            if(!snap_ok) o_lat_valid <= 1'b0;
            if(out_evt) begin
                // Every displayed frame has its own output time, including source-frame repeats.
                o_lat_ms <= snap_ok ? ((lat_diff > 32'd999) ? 16'd999 : lat_diff[15:0]) : 16'd0;
                o_lat_valid <= snap_ok;
                o_pub_tgl <= ~o_pub_tgl;
            end
        end
    end

endmodule
