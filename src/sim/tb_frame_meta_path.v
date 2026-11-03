`timescale 1ns/1ps
// Real writer/reader/FIFOs, address-indexed DDR model and mixer endpoint. The model does not
// validate the memory controller, physical CDC or HDMI transmitter. It checks that metadata
// identifies the frame actually stored/read, rather than one inferred from a stimulus slot.
module tb_frame_meta_path;
    parameter integer CAP_LINES=720;
    localparam integer WORDS=240*CAP_LINES;
    reg csi=0,ddr=0,pix=0,rst=0;
    always #5 csi=~csi;
    always #3.75 ddr=~ddr;
    always #6.666 pix=~pix;
    reg cam_fs=0,cam_valid=0,display_on=0,drop_reads=0;
    reg [95:0] cam_data=0;
    wire packed_fs,packed_valid;wire [127:0] packed_data;
    reg [4:0] tim=0;
    wire fs,wr_en,wr_busy,rd_en,rd_busy,read_fault,capture_fault,out_tgl,pub,valid,short_,over;
    wire [1:0] wp,rp,state;
    wire [24:0] wa,ra;
    wire [127:0] wd;
    wire [23:0] rgb,hdmi_rgb,fid;
    wire [15:0] latency;
    wire hd,hv,hh;
    reg rd_valid=0;
    reg [127:0] rd_data=0;
    reg [127:0] mem[0:4*WORDS-1];
    integer errors=0,checks=0,test_done=0,writes=0,display_frames=0,pixels=0;
    integer slot_words[0:3],slot_id[0:3];
    integer model_cycles=0,slot_tin[0:3],expected_slot=0,expected_fid=0;
    integer expected_ms=0,publications=0,endpoints=0;
    reg prev_pub=0,prev_out=0;
    integer osd_checks=0;
    // Use the exact packer preceding video_in in the production ISP. user accompanies its
    // first 96-bit beat; there is no artificial blanking between the marker and frame data.
    data_96bit_to_128bit packer(.I_clk(csi),.I_rst_n(rst),.I_96b_frame_start(cam_fs),
        .I_96b_valid(cam_valid),.I_96b_data(cam_data),.O_128b_frame_start(packed_fs),
        .O_128b_valid(packed_valid),.O_128b_data(packed_data));
    video_in vi(.I_rst_n(rst),.I_camera_clk(csi),.I_camera_frame_start(packed_fs),
        .I_camera_valid(packed_valid),.I_camera_data(packed_data),.I_mipi_rx_error(1'b0),
        .I_ddr_clk(ddr),.I_display_pause(1'b0),.I_video_out_rd_busy(rd_busy),
        .O_video_in_wr_busy(wr_busy),.O_video_out_rp(rp),.O_frame_start(fs),.O_wr_slot(wp),
        .O_capture_fault(capture_fault),
        .O_ddr_user_wr_en(wr_en),.O_ddr_user_addr(wa),.O_ddr_user_wr_data(wd),.I_ddr_user_ready(1'b1));
    video_out vo(.I_rst_n(rst),.I_ddr_clk(ddr),.I_video_in_wr_busy(wr_busy || !display_on),
        .I_video_out_rp(rp),.O_video_out_rd_busy(rd_busy),.O_ddr_user_rd_en(rd_en),
        .O_ddr_user_addr(ra),.I_ddr_user_ready(1'b1),.I_ddr_user_rd_valid(rd_valid),
        .I_ddr_user_rd_data(rd_data),.I_dsi_clk(pix),.I_video_vsync(tim[4]),
        .I_video_rd_en(tim[2]),.O_vdieo_data(rgb),.O_read_fault(read_fault));
    frame_meta #(.EXPECTED_BEATS(WORDS)) fm(.clk(ddr),.rst_n(rst),.i_frame_start(fs),
        .i_wr_slot(wp),.i_wr_en(wr_en),.i_wr_busy(wr_busy),.i_rp(rp),.i_vsync(tim[4]),
        .i_out_tgl(out_tgl),.i_read_fault(read_fault),.o_lat_ms(latency),.o_lat_valid(valid),
        .i_capture_fault(capture_fault),
        .o_pub_tgl(pub),.o_state(state),.o_frame_id(fid),.o_short(short_),.o_over(over));
    // Reader RGB has two registered unpacking stages; keep the associated timing aligned.
    reg [4:0] t1=0,t2=0;
    always @(posedge pix) begin t1<=tim;t2<=t1;end
    hdmi_mixer #(.H_OFFSET(0),.V_OFFSET(0),.STATUS_OSD(1),.LAT_OSD(1)) mix(
        .I_clk(pix),.I_rst_n(rst),.I_video_vsync(t2[4]),.I_video_hsync(t2[3]),
        .I_video_de(t2[2]),.I_video_user(t2[1]),.I_video_last(t2[0]),.I_debug_status(4'hf),
        .I_mode(4'd0),.I_thresh(8'd96),.I_ae_src_auto(1'b1),.I_video_rd_data(rgb),
        .I_det_valid(1'b0),.I_det_cls(2'd0),.I_det_area(20'd0),.I_det_xmin(12'd0),
        .I_det_xmax(12'd0),.I_det_ymin(12'd0),.I_det_ymax(12'd0),
        .I_mv_valid(1'b0),.I_mv_count(8'd0),.I_mv_overflow(1'b0),.I_mv_global_change(1'b0),
        .I_mv_r0(48'd0),.I_mv_r1(48'd0),.I_mv_r2(48'd0),.I_mv_r3(48'd0),
        .I_lat_ms(latency),.I_lat_valid(valid),.I_lat_tgl(pub),.O_video_rd_en(),
        .O_hdmi_data(hdmi_rgb),.O_hdmi_vsync(hv),.O_hdmi_hsync(hh),.O_hdmi_de(hd),
        .O_out_first_tgl(out_tgl));
    function integer slot_of(input [24:0] a);begin slot_of=a/7000000;end endfunction
    function integer offset_of(input [24:0] a);begin offset_of=(a%7000000)/8;end endfunction
    integer s,off;
    always @(posedge ddr) begin
        if(!rst) begin model_cycles=0;rd_valid<=0;prev_pub=0;end
        else begin
            if(fs) begin slot_tin[wp]=model_cycles/133333;slot_words[wp]=0;end
            if(wr_en) begin
                s=slot_of(wa);off=offset_of(wa);
                checks=checks+1;
                if(s>3 || off>=WORDS || off!=slot_words[s]) begin
                    errors=errors+1;if(errors<10)$display("FAIL DDR write slot=%0d offset=%0d count=%0d",s,off,slot_words[s]);
                end else begin mem[s*WORDS+off]<=wd;slot_words[s]=slot_words[s]+1;end
                if(off==0) slot_id[s]=wd[127:104];
                writes=writes+1;
            end
            rd_valid<=rd_en && !drop_reads;
            if(rd_en && !drop_reads) begin
                s=slot_of(ra);off=offset_of(ra);
                if(s<4 && off<WORDS) rd_data<=mem[s*WORDS+off];else rd_data<=0;
            end
            if(vo.S_video_frame_start) begin
                expected_slot=rp;expected_fid=slot_id[rp];
            end
            if(fm.out_evt) expected_ms=model_cycles/133333-slot_tin[expected_slot];
            model_cycles=model_cycles+1;
            #1;
            if(pub!=prev_pub) begin
                publications=publications+1;prev_pub=pub;checks=checks+1;
                if(!drop_reads && (valid!==1'b1 || fid!==expected_fid || latency!==expected_ms)) begin
                    errors=errors+1;$display("FAIL path metadata fid=%0d/%0d valid=%b ms=%0d/%0d slot=%0d",fid,expected_fid,valid,latency,expected_ms,expected_slot);
                end
            end
        end
    end
    // First decoded pixel after the reader's two stages must encode the same source frame id
    // as the address-indexed memory. Compare every active pixel before any overlay.
    always @(posedge pix) begin
        #1;
        if(rst && t2[2] && !drop_reads) begin
            pixels=pixels+1;checks=checks+1;
            if(rgb!==expected_fid) begin
                errors=errors+1;if(errors<10)$display("FAIL read pixel=%h want fid=%h time=%0t",rgb,expected_fid,$time);
            end
        end
        if(rst && out_tgl!=prev_out) begin endpoints=endpoints+1;prev_out=out_tgl;end
    end
    reg [7:0] ref_char=0;reg [3:0] ref_row=0;wire [15:0] ref_bits;
    osd_char_lib font(.I_char(ref_char),.I_row(ref_row),.O_row_bits(ref_bits));
    integer rx=0,ry=0,idx,qi;
    reg [23:0] ref_color[0:4];reg ref_region[0:4];
    always @(posedge pix) begin
        if(!rst) begin
            rx=0;ry=0;
            for(qi=0;qi<5;qi=qi+1)begin ref_region[qi]<=0;ref_color[qi]<=0;end
        end else begin
            if(tim[2] && tim[1])begin rx=0;ry=0;end
            idx=(rx-192)/16;ref_row=ry-16;
            case(idx)
                17:ref_char=drop_reads?"I":"L";18:ref_char=drop_reads?"N":"A";
                19:ref_char=drop_reads?"V":"T";20:ref_char=drop_reads?"A":":";
                21:ref_char=drop_reads?"L":("0"+expected_ms/100);
                22:ref_char=drop_reads?"I":("0"+(expected_ms/10)%10);
                23:ref_char=drop_reads?"D":("0"+expected_ms%10);
                24:ref_char=drop_reads?0:"M";25:ref_char=drop_reads?0:"S";
                default:ref_char=0;
            endcase
            #0.01;
            ref_region[0]<=tim[2] && rx>=464 && rx<608 && ry>=16 && ry<32;
            ref_color[0]<=ref_bits[15-(rx%16)]?24'hff0000:expected_fid;
            for(qi=1;qi<5;qi=qi+1)begin ref_region[qi]<=ref_region[qi-1];ref_color[qi]<=ref_color[qi-1];end
            if(tim[2])begin if(tim[0])begin rx=0;ry=ry+1;end else rx=rx+1;end
            #0.99;
            // Underflow data is unspecified; only compare the INVALID glyph's red pixels.
            if(ref_region[4] && (!drop_reads || ref_color[4]==24'hff0000))begin
                osd_checks=osd_checks+1;
                if(hdmi_rgb!==ref_color[4])begin
                    errors=errors+1;if(errors<10)$display("FAIL real latency glyph rgb=%h/%h",hdmi_rgb,ref_color[4]);
                end
            end
        end
    end
    integer j,r,f,old_writes,old_endpoints,old_publications;
    task capture(input integer id);
        begin
            old_writes=writes;
            @(negedge csi);cam_fs=1;cam_valid=1;cam_data={4{id[23:0]}};
            for(r=0;r<CAP_LINES;r=r+1) begin
                if(r>0)begin @(negedge csi);cam_valid=1;end
                repeat(319)begin @(negedge csi);cam_fs=0;end
                @(negedge csi);cam_valid=0;
                // This is bounded ready scheduling, not forcing a DUT internal signal.
                while(writes<old_writes+(r+1)*240) @(negedge ddr);
                repeat(8) @(negedge csi);
            end
            repeat(8) @(negedge ddr);
            checks=checks+1;
            if(writes-old_writes!=WORDS) begin errors=errors+1;$display("FAIL captured beats");end
            $display("INFO capture fid=%0d beats=%0d",id,writes-old_writes);
        end
    endtask
    task display_frame;
        begin
            old_endpoints=endpoints;old_publications=publications;
            @(negedge pix);tim=5'b10000;
            // The active region follows a real blanking/preload interval.
            repeat(60) @(negedge pix);
            tim=0;display_on=1;
            repeat(600) @(negedge pix);
            for(r=0;r<36;r=r+1) begin
                for(j=0;j<1280;j=j+1) begin
                    @(negedge pix);tim={2'b00,1'b1,(r==0 && j==0),(j==1279)};
                end
                repeat(370) begin @(negedge pix);tim=0;end
            end
            repeat(60) begin @(negedge pix);tim=0;end
            checks=checks+1;display_frames=display_frames+1;
            if(endpoints-old_endpoints!=1 || publications-old_publications!=1) begin
                errors=errors+1;$display("FAIL endpoint/pub count %0d/%0d",endpoints-old_endpoints,publications-old_publications);
            end
            if(!drop_reads && (mix.lat_shown_vld!==1'b1 || mix.g_lat.lat_shown!==expected_ms ||
                {mix.lat_h,mix.lat_t,mix.lat_o} !== {4'(expected_ms/100),4'((expected_ms/10)%10),4'(expected_ms%10)})) begin
                errors=errors+1;$display("FAIL real mixer readout ms=%0d expected=%0d vld=%b",mix.g_lat.lat_shown,expected_ms,mix.lat_shown_vld);
            end
            display_on=0;
            // Drain an already-started 240-word burst before the next acquisition.
            repeat(400) @(negedge ddr);
        end
    endtask
    initial begin
        for(j=0;j<4;j=j+1) begin slot_words[j]=0;slot_id[j]=0;slot_tin[j]=0;end
        repeat(30) @(negedge csi);rst=1;
        for(f=1;f<=8;f=f+1) begin
            capture(f);
            if(f>=3) display_frame;
        end
        // Commit the eighth full acquisition and verify exact production beat count.
        @(negedge csi);cam_fs=1;@(negedge csi);cam_fs=0;
        repeat(30) @(negedge csi);
        checks=checks+1;
        if(short_!==0 || over!==0 || capture_fault!==0 || fm.st[3]!==2'd2 || fm.sbeats[3]!==WORDS || writes!=8*WORDS) begin
            errors=errors+1;$display("FAIL full-frame commit words=%0d short=%b over=%b st3=%0d beats3=%0d",writes,short_,over,fm.st[3],fm.sbeats[3]);
        end
        // Real FIFO starvation must withdraw latency validity and be recoverable at next vsync.
        drop_reads=1;display_frame;
        checks=checks+1;
        if(read_fault!==1'b1 || valid!==1'b0 || mix.lat_shown_vld!==1'b0) begin
            errors=errors+1;$display("FAIL read underflow not invalidated");
        end
        drop_reads=0;display_frame;
        checks=checks+1;
        if(read_fault!==0 || valid!==1'b1) begin errors=errors+1;$display("FAIL underflow recovery");end
        test_done=1;
        if(errors==0)$display("PASS frame_meta_path checks=%0d writes=%0d pixels=%0d display_frames=%0d osd_checks=%0d",checks,writes,pixels,display_frames,osd_checks);
        else $display("FAIL frame_meta_path errors=%0d checks=%0d",errors,checks);
        $finish;
    end
    initial begin #100000000;if(!test_done)begin $display("FAIL frame_meta_path TIMEOUT");$finish;end end
endmodule
