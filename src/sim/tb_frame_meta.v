`timescale 1ns/1ps
// P5: frame identity + latency bookkeeping (frame_meta) and the latency readout in hdmi_mixer.
//
// Module/OSD checks; sim_frame_meta_path separately tests the actual connected data path:
//   A. video_in taps (O_frame_start / O_wr_slot): the tap must name exactly the slot whose base
//      address video_in latches at the same frame start, and it must advance 0,1,2,3 per frame.
//   B. frame_meta unit logic: commit vs stale (SHORT/OVERRUN), slot rotation, generation
//      mismatch, REPEAT suppression, reset semantics (INVALID, never a fabricated 0 ms) and the
//      millisecond arithmetic with an exact expected value.
//   C. hdmi_mixer latency OSD: full-raster per-pixel comparison against an independent
//      osd_char_lib instance for "LAT:100MS", "LAT:033MS" and "INVALID", plus the measurement
//      endpoint (O_out_first_tgl) toggling exactly once per display frame.
//
// The ddr->pixel crossing is exercised for real: the payload/toggle in section C are driven from
// the ddr clock domain, so hdmi_mixer's three-stage event / two-stage payload synchronisers see
// the same pattern frame_meta produces.
module tb_frame_meta;
    integer errors=0, checks=0, test_done=0;
    integer red_lat=0, tgl_seen=0, tap_checks=0, osd_frames=0;

    // ---------------- clocks / reset ----------------
    reg csi_clk=0, ddr_clk=0, pix_clk=0;
    always #5.0   csi_clk = ~csi_clk;    // 100 MHz stand-in for the camera-side clock
    always #3.75  ddr_clk = ~ddr_clk;    // 133.333 MHz user/DDR clock
    always #6.666 pix_clk = ~pix_clk;    // ~75 MHz HDMI pixel clock
    reg rst_n=0;
    // ddr cycle counter: lets the latency stimulus land on an exact cycle boundary, so the
    // expected millisecond value is exact rather than phase dependent.
    integer cyc=0;
    always @(posedge ddr_clk) if(!rst_n) cyc=0; else cyc = cyc + 1;

    // ================= A. video_in taps =================
    reg         cam_fs=0, cam_valid=0;
    reg [127:0] cam_data=0;
    wire [1:0]  vi_rp;
    wire [24:0] vi_addr;
    wire        tap_fs;
    wire [1:0]  tap_slot;

    video_in u_video_in(
        .I_rst_n(rst_n),
        .I_camera_clk(csi_clk),
        .I_camera_frame_start(cam_fs),
        .I_camera_valid(cam_valid),
        .I_camera_data(cam_data),
        .I_mipi_rx_error(1'b0),
        .I_ddr_clk(ddr_clk),
        .I_display_pause(1'b0),
        .I_video_out_rd_busy(1'b0),
        .O_video_in_wr_busy(),
        .O_video_out_rp(vi_rp),
        .O_ddr_user_wr_en(),
        .O_ddr_user_addr(vi_addr),
        .O_ddr_user_wr_data(),
        .I_ddr_user_ready(1'b1),
        .O_frame_start(tap_fs),
        .O_wr_slot(tap_slot)
    );

    // Section A checker: capture the slot at the frame-start cycle, then compare the base address
    // one ddr cycle later (that is when video_in's address block has latched BASE[wp]).
    reg        tap_pending=0;
    reg [1:0]  tap_captured=0;
    reg [1:0]  tap_seq_expect=0;
    reg        secA_done=0;
    reg [24:0] base_expect;
    always @(posedge ddr_clk) begin
        if(!rst_n) begin
            tap_pending<=1'b0; tap_captured<=2'd0; tap_seq_expect<=2'd0;
        end else if(!secA_done) begin
            if(tap_fs) begin
                tap_captured <= tap_slot;
                tap_pending  <= 1'b1;
            end else if(tap_pending) begin
                tap_pending <= 1'b0;
                case(tap_captured)
                    2'd0: base_expect = 25'd0;
                    2'd1: base_expect = 25'd7000000;
                    2'd2: base_expect = 25'd14000000;
                    default: base_expect = 25'd21000000;
                endcase
                tap_checks = tap_checks + 1;
                if(vi_addr !== base_expect) begin
                    errors = errors + 1;
                    $display("FAIL video_in tap base: slot=%0d addr=%0d want=%0d time=%0t",
                             tap_captured, vi_addr, base_expect, $time);
                end
                if(tap_captured !== tap_seq_expect) begin
                    errors = errors + 1;
                    $display("FAIL video_in tap slot order: got=%0d want=%0d time=%0t",
                             tap_captured, tap_seq_expect, $time);
                end
                tap_seq_expect <= tap_seq_expect + 2'd1;
            end
        end
    end

    // ================= B. frame_meta unit =================
    localparam integer MS_DIV_TB = 100;   // 100 ddr cycles per "ms" in this TB (keeps runs short)
    localparam integer BEATS_TB  = 8;     // beats per complete frame in this TB
    reg         fm_fs=0;
    reg [1:0]   fm_slot=0;
    reg         fm_wr=0;
    reg [1:0]   fm_rp=2'd0;
    reg         fm_vsync=0;
    reg         fm_out=0;
    wire [15:0] fm_lat;
    wire        fm_vld, fm_pub, fm_short, fm_over;
    reg fm_read_fault=0;
    wire [1:0]  fm_state;
    wire [23:0] fm_fid;

    frame_meta #(.EXPECTED_BEATS(BEATS_TB), .BEAT_TOL(0), .MS_DIV(MS_DIV_TB)) u_fm(
        .clk(ddr_clk), .rst_n(rst_n),
        .i_frame_start(fm_fs), .i_wr_slot(fm_slot), .i_wr_en(fm_wr),
        .i_wr_busy(1'b0), .i_read_fault(fm_read_fault),
        .i_capture_fault(1'b0),
        .i_rp(fm_rp), .i_vsync(fm_vsync), .i_out_tgl(fm_out),
        .o_lat_ms(fm_lat), .o_lat_valid(fm_vld), .o_pub_tgl(fm_pub),
        .o_state(fm_state), .o_frame_id(fm_fid), .o_short(fm_short), .o_over(fm_over)
    );

    // ================= mixer + latency OSD =================
    reg  ovr_en=1'b0;
    reg  [15:0] ovr_lat=16'd0;
    reg         ovr_vld=0;
    reg         ovr_tgl=0;
    wire [15:0] mix_lat = ovr_en ? ovr_lat : fm_lat;
    wire        mix_vld = ovr_en ? ovr_vld : fm_vld;
    wire        mix_tgl = ovr_en ? ovr_tgl : fm_pub;

    reg [4:0] tim_pix=0;
    reg [3:0] mode=0;
    reg [7:0] threshold=8'd96;
    wire [23:0] rgb;
    wire vs,hs,de,out_tgl;
    hdmi_mixer #(.H_OFFSET(0),.V_OFFSET(0),.STATUS_OSD(1),.LAT_OSD(1)) dut(
        .I_clk(pix_clk),.I_rst_n(rst_n),
        .I_video_vsync(tim_pix[4]),.I_video_hsync(tim_pix[3]),
        .I_video_de(tim_pix[2]),.I_video_user(tim_pix[1]),.I_video_last(tim_pix[0]),
        .I_ae_src_auto(1'b1),
        .I_debug_status(4'b1111),.I_mode(mode),.I_thresh(threshold),
        .I_det_valid(1'b0),.I_det_cls(2'd0),.I_det_area(20'd0),
        .I_det_xmin(12'd0),.I_det_xmax(12'd0),.I_det_ymin(12'd0),.I_det_ymax(12'd0),
        .I_mv_valid(1'b0),.I_mv_count(8'd0),.I_mv_overflow(1'b0),.I_mv_global_change(1'b0),
        .I_mv_r0(48'd0),.I_mv_r1(48'd0),.I_mv_r2(48'd0),.I_mv_r3(48'd0),
        .I_lat_ms(mix_lat),.I_lat_valid(mix_vld),.I_lat_tgl(mix_tgl),
        .O_video_rd_en(),.I_video_rd_data(24'h123456),
        .O_hdmi_vsync(vs),.O_hdmi_hsync(hs),.O_hdmi_de(de),.O_hdmi_data(rgb),
        .O_out_first_tgl(out_tgl)
    );

    reg [7:0] ch=0;
    reg [3:0] fontrow=0;
    wire [15:0] bits;
    osd_char_lib reference_font(.I_char(ch),.I_row(fontrow),.O_row_bits(bits));
    reg  [14:0] ref_addr=0;
    wire [24:0] ref_pixel;
    anlogic_logo_rom reference_logo(.I_addr(ref_addr),.O_pixel(ref_pixel));

    reg region=0, logo_region=0;
    reg [23:0] expected=24'h123456;
    reg [23:0] eq[0:2];
    reg [2:0]  tq[0:2];
    reg        regionq[0:2];
    integer warmup=0, q;
    reg [3:0]  exp_h=0, exp_t=0, exp_o=0;
    reg        exp_vld=0;
    reg        ovr_capture=0;   // when set, section C counts the region's red pixels

    always @(posedge pix_clk) begin
        if(!rst_n) warmup <= 0;
        else if(warmup < 20) warmup <= warmup + 1;
        if(!rst_n) begin
            for(q=0;q<3;q=q+1) begin eq[q]<=0;tq[q]<=0;regionq[q]<=0; end
        end else begin
            eq[0]<=expected;tq[0]<=tim_pix[4:2];regionq[0]<=region;
            for(q=1;q<3;q=q+1) begin eq[q]<=eq[q-1];tq[q]<=tq[q-1];regionq[q]<=regionq[q-1]; end
        end
        #1;
        if(rst_n && !test_done && warmup > 9) begin
            checks=checks+1;
            if({vs,hs,de}!==tq[2] || rgb!==eq[2]) begin
                errors=errors+1;
                if(errors<12) $display("FAIL OSD rgb=%h/%h tim=%b/%b x2d=%0d y2d=%0d lat=%0d vld=%b time=%0t",
                    rgb,eq[2],{vs,hs,de},tq[2],dut.S_x_2d,dut.S_y_2d,dut.g_lat.lat_shown,dut.lat_shown_vld,$time);
            end
            if(ovr_capture && regionq[2] && rgb==24'hff0000) red_lat=red_lat+1;
        end
    end

    // one display frame of the small raster: 36 rows x 640 columns, user pulses at (0,0)
    task run_raster(input [3:0] dh, input [3:0] dt, input [3:0] do_, input vld);
        integer r,c,idx,localx;
        reg [7:0] cx;
        begin
            for(r=0;r<36;r=r+1) begin
                for(c=0;c<640;c=c+1) begin
                    @(negedge pix_clk);
                    tim_pix = {2'b00,1'b1,(r==0 && c==0),(c==639)};
                    region  = (r>=16 && r<32 && c>=192 && c<608);
                    localx  = c-192; idx = localx/16;
                    case(idx)
                        0:cx="M";1:cx="O";2:cx="D";3:cx="E";4:cx=":";
                        5:cx=8'h30;                                   // mode = 0
                        7:cx="T";8:cx="H";9:cx=":";
                        10:cx=8'h30;11:cx=8'h39;12:cx=8'h36;          // threshold = 96
                        13:cx="A";14:cx="U";15:cx="T";16:cx="O";      // AUTO (I_ae_src_auto=1)
                        17:cx=vld?"L":"I";
                        18:cx=vld?"A":"N";
                        19:cx=vld?"T":"V";
                        20:cx=vld?":":"A";
                        21:cx=vld?(8'h30+dh):"L";
                        22:cx=vld?(8'h30+dt):"I";
                        23:cx=vld?(8'h30+do_):"D";
                        24:cx=vld?"M":8'h00;
                        25:cx=vld?"S":8'h00;
                        default:cx=8'h00;
                    endcase
                    ch = cx;
                    fontrow = (r>=16 && r<32) ? (r-16) : 4'd0;
                    logo_region = (r<160 && c<160);
                    ref_addr = logo_region ? (r*160+c) : 15'd0;
                    #1;
                    if(region && bits[15-(localx%16)]) expected=24'hff0000;
                    else if(logo_region && ref_pixel[24]) expected=ref_pixel[23:0];
                    else expected=24'h123456;
                end
                repeat(5) begin @(negedge pix_clk); tim_pix=0; region=0; logo_region=0; expected=24'h123456; end
            end
            repeat(10) begin @(negedge pix_clk); tim_pix=0; region=0; logo_region=0; expected=24'h123456; end
        end
    endtask

    // one acquisition frame: frame start in slot s followed by exactly n accepted write beats
    reg [31:0] cyc_fs_mon=0, cyc_out_mon=0;
    always @(posedge ddr_clk) if(rst_n && fm_fs)  cyc_fs_mon  = cyc;
    always @(posedge ddr_clk) if(rst_n && u_fm.out_evt) cyc_out_mon = cyc;
    task acq(input [1:0] s, input integer n);
        integer j;
        begin
            @(negedge ddr_clk);
            fm_slot = s;
            fm_fs   = 1'b1;
            @(negedge ddr_clk);
            fm_fs   = 1'b0;
            for(j=0;j<n;j=j+1) begin
                @(negedge ddr_clk);
                fm_wr = 1'b1;
            end
            @(negedge ddr_clk);
            fm_wr = 1'b0;
        end
    endtask

    // ---------------- stimulus ----------------
    integer i, f, exp_ms;
    integer lat_prev;
    reg     pub_prev;
    reg [1:0] slot_i;
    integer cyc_fs0=0;
    initial begin
        // ---------- section A ----------
        rst_n=0;
        repeat(6) @(negedge ddr_clk);
        rst_n=1;
        repeat(4) @(negedge ddr_clk);
        for(f=0; f<5; f=f+1) begin
            @(negedge ddr_clk); cam_fs=1'b1; @(negedge csi_clk); cam_fs=1'b0;
            // a few words only: no 240-beat burst is launched, so the base address stays latched
            for(i=0;i<8;i=i+1) begin
                cam_valid=1'b1; cam_data={120'd0, 8'h11};
                @(negedge csi_clk);
            end
            cam_valid=1'b0;
            repeat(40) @(negedge ddr_clk);
        end
        repeat(20) @(negedge ddr_clk);
        secA_done=1;
        if(tap_checks != 5) begin
            errors=errors+1; $display("FAIL tap checks=%0d (want 5)",tap_checks);
        end
        $display("INFO section A: tap_checks=%0d errors=%0d",tap_checks,errors);

        // ---------- section B: frame_meta unit ----------
        rst_n=0; fm_fs=0; fm_wr=0; fm_slot=0; fm_vsync=0; fm_out=0; fm_rp=2'd0;
        repeat(8) @(negedge ddr_clk);
        rst_n=1;
        // release edge = ms phase zero; the next posedge is the first counted cycle
        @(negedge ddr_clk);

        // R4: right after reset, a display snapshot plus an output event with no committed frame
        // must report INVALID - never a fabricated 0 ms.
        fm_rp=2'd0;
        @(negedge ddr_clk); fm_vsync=1'b1; @(negedge ddr_clk); fm_vsync=1'b0;
        repeat(4) @(negedge ddr_clk);
        @(negedge ddr_clk); fm_out=~fm_out;
        repeat(8) @(negedge ddr_clk);
        if(fm_lat !== 16'd0 || fm_vld !== 1'b0) begin
            errors=errors+1;
            $display("FAIL reset semantics: lat=%0d vld=%b (want 0/0 = INVALID)",fm_lat,fm_vld);
        end

        // frame 0 -> slot 0, 8 beats
        acq(2'd0, BEATS_TB);
        cyc_fs0 = cyc_fs_mon;                      // cycle of frame 0's start edge
        // frame 1 -> slot 1 starts now; this finalises slot 0 as COMMITTED
        acq(2'd1, BEATS_TB);
        // display snapshot of slot 0 (the committed frame) at a vsync edge
        fm_rp=2'd0;
        @(negedge ddr_clk); fm_vsync=1'b1; @(negedge ddr_clk); fm_vsync=1'b0;
        // exactly 10000 ddr cycles after frame 0's start edge -> exactly 100 ms (MS_DIV_TB=100)
        while(cyc < (cyc_fs0 + 9999)) @(negedge ddr_clk);
        fm_out=~fm_out;
        repeat(8) @(negedge ddr_clk);
        exp_ms = ((cyc_out_mon-1)/MS_DIV_TB) - ((cyc_fs0-1)/MS_DIV_TB);
        if(fm_lat !== exp_ms[15:0] || fm_vld !== 1'b1) begin
            errors=errors+1;
            $display("FAIL latency: lat=%0d vld=%b (want %0d, cyc %0d->%0d)",
                     fm_lat,fm_vld,exp_ms,cyc_fs0,cyc_out_mon);
        end
        if(fm_state !== 2'd2) begin
            errors=errors+1; $display("FAIL snapshot state=%0d (want COMMITTED=2)",fm_state);
        end

        // The same source frame displayed later has a later output time and must get a fresh
        // reading/publication. Its age must grow rather than freezing at the first display.
        lat_prev = fm_lat; pub_prev = fm_pub;
        fm_rp=2'd0;                                // same slot -> same frame id
        @(negedge ddr_clk); fm_vsync=1'b1; @(negedge ddr_clk); fm_vsync=1'b0;
        repeat(300) @(negedge ddr_clk);            // let the ms counter advance
        @(negedge ddr_clk); fm_out=~fm_out;
        repeat(8) @(negedge ddr_clk);
        if(fm_lat <= lat_prev || fm_pub === pub_prev) begin
            errors=errors+1;
            $display("FAIL repeat age: lat %0d -> %0d, pub %b -> %b",
                     lat_prev,fm_lat,pub_prev,fm_pub);
        end

        // SHORT: a frame with too few beats must not commit
        acq(2'd2, BEATS_TB-1);
        acq(2'd3, BEATS_TB);                       // finalises slot 2 -> STALE + short
        repeat(3) @(negedge ddr_clk);
        if(fm_short !== 1'b1 || fm_over !== 1'b0) begin
            errors=errors+1; $display("FAIL short flag: short=%b over=%b",fm_short,fm_over);
        end
        // OVERRUN: too many beats
        acq(2'd0, BEATS_TB+1);
        acq(2'd1, BEATS_TB);                       // finalises slot 0 -> STALE + over
        repeat(3) @(negedge ddr_clk);
        if(fm_over !== 1'b1 || fm_short !== 1'b0) begin
            errors=errors+1; $display("FAIL over flag: short=%b over=%b",fm_short,fm_over);
        end

        // A genuine last accepted beat on the next frame-start edge addresses the previous
        // frame's old base. Include it, and leave the new frame's counter at zero.
        acq(2'd2, BEATS_TB-1);
        @(negedge ddr_clk);
        fm_slot=2'd3; fm_wr=1'b1; fm_fs=1'b1;
        @(negedge ddr_clk); fm_fs=1'b0; fm_wr=1'b0;
        repeat(3) @(negedge ddr_clk);
        if(fm_short !== 1'b0 || fm_over !== 1'b0 || u_fm.st[2]!==2'd2 ||
           u_fm.sbeats[2]!==BEATS_TB || u_fm.sbeats[3]!==0) begin
            errors=errors+1;
            $display("FAIL boundary beat: short=%b over=%b old=%0d new=%0d",fm_short,fm_over,u_fm.sbeats[2],u_fm.sbeats[3]);
        end

        // snapshot a committed slot 1, then commit slot 1 a second time so the snapshot's
        // generation is stale -> the reading must be reported INVALID
        acq(2'd2, BEATS_TB);
        acq(2'd3, BEATS_TB);                       // finalises slot 2
        repeat(3) @(negedge ddr_clk);
        fm_rp=2'd1;
        @(negedge ddr_clk); fm_vsync=1'b1; @(negedge ddr_clk); fm_vsync=1'b0;
        repeat(6) @(negedge ddr_clk);
        slot_i = 2'd0;
        for(f=0; f<5; f=f+1) begin
            acq(slot_i, BEATS_TB);
            slot_i = slot_i + 2'd1;
        end
        @(negedge ddr_clk); fm_out=~fm_out;
        repeat(8) @(negedge ddr_clk);
        if(fm_vld !== 1'b0) begin
            errors=errors+1; $display("FAIL generation mismatch not flagged: vld=%b",fm_vld);
        end

        $display("INFO section B: lat=%0d state=%0d time=%0t",fm_lat,fm_state,$time);

        // ---------- section C: latency OSD rendering ----------
        // drive the payload/toggle from the ddr domain (the crossing style frame_meta uses)
        ovr_en=1'b1; ovr_lat=16'd100; ovr_vld=1'b1; ovr_tgl=1'b0;
        repeat(6) @(negedge ddr_clk);
        ovr_tgl=1'b1;
        repeat(6) @(negedge ddr_clk);
        wait(dut.g_lat.bcd_busy==1'b0);
        repeat(20) @(negedge pix_clk);
        red_lat=0; ovr_capture=1;
        run_raster(4'd1,4'd0,4'd0,1'b1);       // LAT:100MS
        osd_frames=osd_frames+1;
        if(red_lat==0) begin errors=errors+1; $display("FAIL LAT:100MS rendered no glyph pixels"); end

        ovr_lat=16'd33;
        repeat(4) @(negedge ddr_clk); ovr_tgl=1'b0;
        repeat(6) @(negedge ddr_clk);
        wait(dut.g_lat.bcd_busy==1'b0);
        repeat(20) @(negedge pix_clk);
        red_lat=0;
        run_raster(4'd0,4'd3,4'd3,1'b1);       // LAT:033MS
        osd_frames=osd_frames+1;
        if(red_lat==0) begin errors=errors+1; $display("FAIL LAT:033MS rendered no glyph pixels"); end

        ovr_vld=1'b0;
        repeat(4) @(negedge ddr_clk); ovr_tgl=1'b1;
        repeat(6) @(negedge ddr_clk);
        wait(dut.g_lat.bcd_busy==1'b0);
        repeat(20) @(negedge pix_clk);
        red_lat=0;
        run_raster(4'd0,4'd0,4'd0,1'b0);       // INVALID
        osd_frames=osd_frames+1;
        if(red_lat==0) begin errors=errors+1; $display("FAIL INVALID rendered no glyph pixels"); end

        // endpoint: O_out_first_tgl must toggle exactly once per display frame
        for(i=0;i<3;i=i+1) begin
            @(negedge pix_clk); ovr_capture=0;
            tgl_seen=0;
            run_raster(4'd0,4'd0,4'd0,1'b0);
            repeat(4) @(negedge pix_clk);
            if(tgl_seen != 1) begin
                errors=errors+1;
                $display("FAIL endpoint: O_out_first_tgl toggled %0d times in one display frame",tgl_seen);
            end
        end
        if(osd_frames < 3) begin errors=errors+1; $display("FAIL osd frames=%0d",osd_frames); end
        if(checks < 1000) begin errors=errors+1; $display("FAIL checks=%0d (too few)",checks); end

        test_done=1;
        if(errors==0) $display("PASS frame_meta checks=%0d tap_checks=%0d osd_frames=%0d errors=0",
                               checks,tap_checks,osd_frames);
        else $display("FAIL frame_meta errors=%0d",errors);
        $finish;
    end

    // endpoint toggle counter (one per display frame)
    reg out_tgl_d=0;
    always @(posedge pix_clk) begin
        if(rst_n) begin
            if(out_tgl ^ out_tgl_d) tgl_seen = tgl_seen + 1;
            out_tgl_d <= out_tgl;
        end
    end

    initial begin
        #40000000;   // 40 ms wall-clock guard
        if(!test_done) begin
            $display("FAIL frame_meta TIMEOUT (errors=%0d checks=%0d)",errors,checks);
            $finish;
        end
    end
endmodule
