`timescale 1ns/1ps
// Source-domain regression for the real ISP packer, frame-head queue and write FIFO.
module tb_frame_meta_input;
    reg csi=0,ddr=0,rst=0,fs=0,vld=0,ready=1;
    always #5 csi=~csi;always #3.75 ddr=~ddr;
    reg [95:0] raw=0;
    wire pfs,pvld,wen,tap,busy,fault;
    wire [1:0] slot;wire[127:0] pd,wd;wire[24:0] addr;
    integer errors=0,checks=0,test_done=0,words=0,f,j,expected_id=0,base_words=0,ddr_cycles=0;
    reg stall=0,hard_stall=0;
    reg verify_words=1;
    function [95:0] raw_pixels(input integer id,input integer x);
        reg [23:0] p0,p1,p2,p3;
        begin p0=id*4096+x;p1=p0+1;p2=p0+2;p3=p0+3;raw_pixels={p0,p1,p2,p3};end
    endfunction
    function [127:0] expected_word(input integer id,input integer n);
        reg [383:0] triple;integer k;
        begin
            for(k=0;k<16;k=k+1)triple[383-k*24 -:24]=id*4096+(n/3)*16+k;
            expected_word=triple[383-(n%3)*128 -:128];
        end
    endfunction
    data_96bit_to_128bit packer(.I_clk(csi),.I_rst_n(rst),.I_96b_frame_start(fs),.I_96b_valid(vld),
        .I_96b_data(raw),.O_128b_frame_start(pfs),.O_128b_valid(pvld),.O_128b_data(pd));
    video_in vi(.I_rst_n(rst),.I_camera_clk(csi),.I_camera_frame_start(pfs),.I_camera_valid(pvld),
        .I_camera_data(pd),.I_mipi_rx_error(1'b0),.I_ddr_clk(ddr),.I_display_pause(1'b0),
        .I_video_out_rd_busy(1'b0),.O_video_in_wr_busy(busy),.O_video_out_rp(),
        .O_frame_start(tap),.O_wr_slot(slot),.O_capture_fault(fault),
        .O_ddr_user_wr_en(wen),.O_ddr_user_addr(addr),.O_ddr_user_wr_data(wd),.I_ddr_user_ready(ready));
    always @(negedge ddr) begin
        ddr_cycles=ddr_cycles+1;
        ready=!hard_stall && (!stall || (ddr_cycles%17<12));
    end
    always @(posedge ddr) if(rst && wen) begin
        words=words+1;checks=checks+1;
        // Every source pixel changes. Independently repack all sixteen pixels per triple, so a
        // duplicate, dropped word, wrong queue wrap or reordered frame header cannot pass.
        if(verify_words && wd!==expected_word(expected_id,words-base_words-1)) begin
            errors=errors+1;if(errors<10)$display("FAIL frame-head word=%0d data=%h expected=%h",words-base_words-1,wd,expected_word(expected_id,words-base_words-1));
        end
    end
    // Separate direct-word path targets full-queue simultaneous pop/push and FS+first-word.
    reg rst2=0,fs2=0,vld2=0,ready2=0;
    reg [127:0] data2=0;
    wire wen2,fault2;wire [127:0] wd2;
    integer sent2=0,writes2=0,full_replace=0;
    function [127:0] direct_word(input integer n);
        reg [31:0] a,b,c,d;
        begin a=n+17;b=n*3;c=n^32'ha5a5a5a5;d=n;direct_word={a,b,c,d};end
    endfunction
    video_in vi2(.I_rst_n(rst2),.I_camera_clk(csi),.I_camera_frame_start(fs2),.I_camera_valid(vld2),
        .I_camera_data(data2),.I_mipi_rx_error(1'b0),.I_ddr_clk(ddr),.I_display_pause(1'b0),
        .I_video_out_rd_busy(1'b0),.O_video_in_wr_busy(),.O_video_out_rp(),
        .O_frame_start(),.O_wr_slot(),.O_capture_fault(fault2),.O_ddr_user_wr_en(wen2),
        .O_ddr_user_addr(),.O_ddr_user_wr_data(wd2),.I_ddr_user_ready(ready2));
    always @(posedge csi)if(rst2)begin
        if(vld2)sent2=sent2+1;
        if(vi2.head_count==32 && vi2.head_push && vi2.head_pop)full_replace=full_replace+1;
    end
    always @(posedge ddr)if(rst2 && wen2)begin
        checks=checks+1;
        if(wd2!==direct_word(writes2))begin errors=errors+1;if(errors<10)$display("FAIL full-queue order at word %0d",writes2);end
        writes2=writes2+1;
    end
    initial begin
        repeat(30)@(negedge csi);rst=1;
        for(f=1;f<=24;f=f+1) begin
            // Different DDR blanking phases plus periodic ready deassertion; first raw beat
            // is concurrent with user, exactly as the actual AWB-to-packer interface.
            repeat(f%17)@(negedge ddr);
            stall=f%2;base_words=words;expected_id=f;
            @(negedge csi);fs=1;vld=1;raw=raw_pixels(f,0);
            for(j=1;j<320;j=j+1)begin @(negedge csi);fs=0;raw=raw_pixels(f,j*4);end
            @(negedge csi);vld=0;
            repeat(600)@(negedge ddr);
            checks=checks+1;
            if(words-base_words!=240 || fault!==0 || vi.head_count!==0) begin
                errors=errors+1;$display("FAIL input phase=%0d words=%0d fault=%b head=%0d",f,words-base_words,fault,vi.head_count);
            end
        end
        // A blocked MC eventually fills both buffers. Loss must be sticky and observable.
        hard_stall=1;verify_words=0;
        @(negedge csi);fs=1;vld=1;
        repeat(959)begin @(negedge csi);fs=0;end
        @(negedge csi);vld=0;
        repeat(30)@(negedge csi);
        checks=checks+1;
        if(fault!==1 || vi.head_count!==32) begin errors=errors+1;$display("FAIL queue overflow not reported");end
        hard_stall=0;repeat(800)@(negedge ddr);
        checks=checks+1;if(fault!==1)begin errors=errors+1;$display("FAIL capture loss not sticky");end
        rst=0;repeat(30)@(negedge csi);rst=1;
        // Reset may be released in the middle of an ISP frame. Ignore its residual words until
        // a new frame marker instead of turning that unavoidable discard into a sticky fault.
        base_words=words;
        @(negedge csi);vld=1;raw={4{24'habcdef}};
        repeat(100)@(negedge csi);
        @(negedge csi);vld=0;repeat(20)@(negedge csi);
        checks=checks+1;
        if(words!=base_words || fault!==0 || vi.head_count!==0)begin errors=errors+1;$display("FAIL pre-frame residual not ignored");end
        base_words=words;expected_id=25;stall=0;verify_words=1;
        @(negedge csi);fs=1;vld=1;raw=raw_pixels(25,0);
        for(j=1;j<320;j=j+1)begin @(negedge csi);fs=0;raw=raw_pixels(25,j*4);end
        @(negedge csi);vld=0;repeat(600)@(negedge ddr);
        checks=checks+1;
        if(words-base_words!=240 || fault!==0)begin errors=errors+1;$display("FAIL source reset recovery");end
        rst2=1;
        @(negedge csi);fs2=1;vld2=1;data2=direct_word(0);
        @(negedge csi);fs2=0;
        while(!(vi2.head_count==32 && vi2.S_fifo_full))begin
            data2=direct_word(sent2);@(negedge csi);
        end
        vld2=0;ready2=1;
        // Resume precisely when space appears in the downstream FIFO, while head_count is
        // still 32. The next source edge reads the old queue word and replaces that address.
        while(vi2.S_fifo_full || vi2.head_count!=32)@(negedge csi);
        vld2=1;data2=direct_word(sent2);@(negedge csi);
        while(sent2<720)begin data2=direct_word(sent2);@(negedge csi);end
        vld2=0;repeat(1500)@(negedge ddr);
        checks=checks+1;
        if(writes2!=720 || sent2!=720 || full_replace<1 || fault2!==0)begin
            errors=errors+1;$display("FAIL full-queue coverage writes=%0d sent=%0d full_replace=%0d fault=%b",writes2,sent2,full_replace,fault2);
        end
        test_done=1;
        if(errors==0)$display("PASS frame_meta_input checks=%0d phases=24 source_frames=25 direct_words=%0d full_replace=%0d",checks,writes2,full_replace);
        else $display("FAIL frame_meta_input errors=%0d",errors);
        $finish;
    end
    initial begin #1000000;if(!test_done)begin $display("FAIL frame_meta_input TIMEOUT");$finish;end end
endmodule
