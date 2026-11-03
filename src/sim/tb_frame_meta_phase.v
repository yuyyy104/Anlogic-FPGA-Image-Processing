`timescale 1ns/1ps
module tb_frame_meta_phase;
    reg clk=0,pix=0,rst=0,fs=0,wr=0,busy=0,vs=0,out=0,fault=0,capture_loss=0;
    always #3.75 clk=~clk;
    always #6.666 pix=~pix;
    reg [1:0] slot=0,rp=0;
    wire [15:0] ms;wire valid,pub,short_,over;wire[23:0] fid;wire[1:0] state;
    integer errors=0,checks=0,test_done=0,frames=0,events=0,cycles=0,expected_ms=0;
    integer tin[0:3];reg [31:0] ticks=0;integer tick_cycles=0;
    frame_meta #(.EXPECTED_BEATS(8),.MS_DIV(16)) fm(.clk(clk),.rst_n(rst),
        .i_frame_start(fs),.i_wr_slot(slot),.i_wr_en(wr),.i_wr_busy(busy),.i_rp(rp),
        .i_vsync(vs),.i_out_tgl(out),.i_read_fault(fault),.o_lat_ms(ms),.o_lat_valid(valid),
        .i_capture_fault(capture_loss),
        .o_pub_tgl(pub),.o_state(state),.o_frame_id(fid),.o_short(short_),.o_over(over));
    reg prev_pub=0;
    always @(posedge clk) begin
        if(!rst) begin cycles=0;ticks=0;tick_cycles=0;prev_pub=0;end
        else begin
            if(fs) tin[slot]=ticks;
            if(fm.out_evt) expected_ms=(ticks-tin[rp]>999)?999:(ticks-tin[rp]);
            if(tick_cycles==15) begin tick_cycles=0;ticks=ticks+1;end
            else tick_cycles=tick_cycles+1;
            cycles=cycles+1;
            #1;
            if(pub!=prev_pub) begin events=events+1;prev_pub=pub;end
        end
    end
    // Exercise the full permitted 20 ns payload skew relative to an undelayed event.
    reg [15:0] src_ms=0;reg src_vld=0,src_tgl=0;
    reg cdc_test=0;integer cdc_events=0;
    wire [15:0] skew_ms;wire skew_vld;
    assign #20 skew_ms=src_ms;
    assign #20 skew_vld=src_vld;
    hdmi_mixer #(.LAT_OSD(1)) mix(.I_clk(pix),.I_rst_n(rst),.I_video_vsync(1'b0),
        .I_video_hsync(1'b0),.I_video_de(1'b0),.I_video_user(1'b0),.I_video_last(1'b0),
        .I_debug_status(4'hf),.I_mode(4'd0),.I_thresh(8'd96),.I_ae_src_auto(1'b1),
        .I_video_rd_data(24'd0),.I_det_valid(1'b0),.I_det_cls(2'd0),.I_det_area(20'd0),
        .I_det_xmin(12'd0),.I_det_xmax(12'd0),.I_det_ymin(12'd0),.I_det_ymax(12'd0),
        .I_mv_valid(1'b0),.I_mv_count(8'd0),.I_mv_overflow(1'b0),.I_mv_global_change(1'b0),
        .I_mv_r0(48'd0),.I_mv_r1(48'd0),.I_mv_r2(48'd0),.I_mv_r3(48'd0),
        .I_lat_ms(skew_ms),.I_lat_valid(skew_vld),.I_lat_tgl(src_tgl),.O_video_rd_en(),
        .O_hdmi_data(),.O_hdmi_vsync(),.O_hdmi_hsync(),.O_hdmi_de(),.O_out_first_tgl());
    always @(posedge pix)if(rst && cdc_test && mix.g_lat.lat_evt)begin
        cdc_events=cdc_events+1;
        #1;
        check(mix.g_lat.lat_shown===src_ms && mix.lat_shown_vld===src_vld,
              "publication consumes a coherent payload at the event, not eventually");
    end
    task check(input ok,input [511:0] msg);
        begin checks=checks+1;if(ok!==1'b1)begin errors=errors+1;if(errors<20)$display("FAIL %0s t=%0t fid=%0d ms=%0d valid=%b",msg,$time,fid,ms,valid);end end
    endtask
    task acq(input [1:0] s,input integer n);
        integer j;
        begin
            @(negedge clk);slot=s;fs=1;@(negedge clk);fs=0;
            // Emulate the REAL tap: after the start, wp already points to the NEXT slot.
            slot=s+2'd1;
            for(j=0;j<n;j=j+1) begin @(negedge clk);wr=1;end
            @(negedge clk);wr=0;
        end
    endtask
    task display(input [1:0] s,input integer phase,input expected_valid,input [23:0] expected_fid);
        integer old_events;
        begin
            old_events=events;rp=s;
            repeat(phase) @(negedge clk);
            @(negedge pix);vs=1;repeat(2) @(negedge pix);vs=0;
            repeat(8) @(negedge clk);
            @(negedge pix);out=~out;
            repeat(10) @(negedge clk);
            check(events==old_events+1,"exactly one publication per display event");
            check(valid===expected_valid && fid===expected_fid,"display slot identity/validity");
            if(expected_valid) check(ms===expected_ms,"independent millisecond arithmetic");
            frames=frames+1;
        end
    endtask
    integer f,j;
    reg [15:0] repeat_age;
    initial begin
        repeat(20) @(negedge clk);rst=1;
        display(0,0,0,0);
        acq(0,8);
        display(0,1,0,1); // first publication while the source is still OCCUPYING
        acq(1,8);
        display(0,2,1,1); // same fid now committed must recover from INVALID
        repeat_age=ms;
        repeat(64) @(negedge clk);
        display(0,3,1,1);
        check(ms>repeat_age,"repeated source frame has a later age");
        // Revoke a measurement AFTER its first pixel, even though no new display event arrives.
        acq(0,8);
        repeat(4) @(negedge clk);
        check(valid===0,"mid-display overwrite withdraws validity");
        acq(1,8);
        display(0,4,1,3);
        fault=1;repeat(8) @(negedge clk);
        check(valid===0,"sticky reader fault withdraws validity");
        fault=0;repeat(8) @(negedge clk);
        display(0,5,1,3);
        // Unfinished burst can contaminate the new base even if its final beat count looks right.
        busy=1;acq(2,8);busy=0;acq(3,8);
        display(2,6,0,5);check(over===1,"unfinished boundary burst cannot certify a frame");
        display(0,0,1,3);
        capture_loss=1;repeat(8)@(negedge clk);
        check(valid===0,"source staging loss withdraws validity");
        // Clear sticky loss with reset, then hit overwrite on the very edge consuming out_evt.
        rst=0;capture_loss=0;repeat(20)@(negedge clk);rst=1;
        acq(0,8);acq(1,8);display(0,0,1,1);
        @(negedge pix);out=~out;
        wait(fm.out_evt);@(negedge clk);slot=0;fs=1;
        @(negedge clk);fs=0;repeat(4)@(negedge clk);
        frames=frames+1;
        check(valid===0,"same-edge overwrite cannot use NBA old state to publish valid");
        // Reset then sweep clock/blanking phases for >256 generations per each of four slots.
        rst=0;fs=0;wr=0;vs=0;out=0;repeat(20) @(negedge clk);rst=1;
        for(f=0;f<1100;f=f+1) begin
            acq(f%4,8);
            if(f>0) display((f-1)%4,f%31,1,f);
        end
        check(fm.sgen[0]===8'd19,"slot generation wraps modulo 256 without mixing frames");
        // Directed wrap seeds avoid pretending a millisecond test simulated three days.
        @(negedge clk);fm.wr_fid=24'hfffffe;fm.r_ms=32'hfffffff0;ticks=32'hfffffff0;
        acq(0,8);acq(1,8);display(0,7,1,24'hffffff);
        acq(2,8);display(1,9,1,24'h000000);
        repeat(16*1100) @(negedge clk);display(1,0,1,24'h000000);
        check(ms===999,"latency saturation");
        acq(3,262146);acq(0,8);
        check(fm.st[3]===2'd3 && over===1 && fm.sbeats[3]===18'h3ffff,"beat overflow saturates and invalidates");
        // Toggle just before the first capture edge; the data arrives 20 ns later.
        @(negedge pix);#6.5;cdc_test=1;src_ms=317;src_vld=1;src_tgl=1;
        repeat(22) @(negedge pix);
        check(mix.g_lat.lat_shown===317 && mix.lat_shown_vld===1 &&
              {mix.lat_h,mix.lat_t,mix.lat_o}===12'h317,"20ns late payload captured atomically");
        check(cdc_events==1,"one consumer event per publication");
        src_vld=0;repeat(8) @(negedge pix);
        check(mix.lat_shown_vld===0,"validity revocation crosses without a data event");
        test_done=1;
        if(errors==0)$display("PASS frame_meta_phase checks=%0d display_frames=%0d publications=%0d",checks,frames,events);
        else $display("FAIL frame_meta_phase errors=%0d checks=%0d",errors,checks);
        $finish;
    end
    initial begin #20000000;if(!test_done)begin $display("FAIL frame_meta_phase TIMEOUT");$finish;end end
endmodule
