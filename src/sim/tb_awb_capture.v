`timescale 1ns/1ps
module tb_awb_capture;
    reg csi=0,ddr=0,rst=0,fs=0,vld=0;reg [95:0] raw=0;
    always #5 csi=~csi;always #3.75 ddr=~ddr;
    wire afs,av,al,pfs,pv,wen,fault;wire [95:0] ar;wire [127:0] pd,wd;
    integer errors=0,checks=0,words=0;reg test_done=0;
    function [23:0] pixel;input integer n;reg [7:0] v;begin v=n%160+32;pixel={v,v,v};end endfunction
    function [95:0] raw_word;input integer n;begin raw_word={pixel(n),pixel(n+1),pixel(n+2),pixel(n+3)};end endfunction
    function [127:0] expected_word;input integer n;reg [383:0] pack;integer k;begin
        for(k=0;k<16;k=k+1)pack[383-k*24 -:24]=pixel((n/3)*16+k);
        expected_word=pack[383-(n%3)*128 -:128];end endfunction
    frame_awb awb(.I_clk(csi),.I_rst_n(rst),.I_tuser(fs),.I_tvalid(vld),.I_tlast(1'b0),.I_tdata(raw),.I_freeze(1'b0),.I_tready(),.O_tready(1'b1),.O_tuser(afs),.O_tvalid(av),.O_tlast(al),.O_tdata(ar),.O_frozen());
    data_96bit_to_128bit packer(.I_clk(csi),.I_rst_n(rst),.I_96b_frame_start(afs),.I_96b_valid(av),.I_96b_data(ar),.O_128b_frame_start(pfs),.O_128b_valid(pv),.O_128b_data(pd));
    video_in vi(.I_rst_n(rst),.I_camera_clk(csi),.I_camera_frame_start(pfs),.I_camera_valid(pv),.I_camera_data(pd),.I_mipi_rx_error(1'b0),.I_ddr_clk(ddr),.I_display_pause(1'b0),.I_video_out_rd_busy(1'b0),.O_video_in_wr_busy(),.O_video_out_rp(),.O_frame_start(),.O_wr_slot(),.O_capture_fault(fault),.O_ddr_user_wr_en(wen),.O_ddr_user_addr(),.O_ddr_user_wr_data(wd),.I_ddr_user_ready(1'b1));
    always @(posedge ddr) if(rst && wen) begin
        checks=checks+1;
        if(wd!==expected_word(words))begin errors=errors+1;if(errors<6)$display("FAIL HD capture word=%0d",words);end
        words=words+1;
    end
    integer x,y;
    initial begin
        repeat(30)@(negedge csi);rst=1;
        // Earliest possible first valid word, concurrent with the frame marker.
        for(y=0;y<720;y=y+1)begin
            for(x=0;x<320;x=x+1)begin @(negedge csi);vld=1;fs=(y==0 && x==0);raw=raw_word(y*1280+x*4);end
            @(negedge csi);vld=0;fs=0;repeat(4)@(negedge csi);
        end
        repeat(800)@(negedge ddr);
        checks=checks+1;if(words!=172800 || fault!==0 || vi.head_count!==0)begin errors=errors+1;$display("FAIL HD complete capture words=%0d fault=%b head=%0d",words,fault,vi.head_count);end
        test_done=1;if(errors==0)$display("PASS awb_capture checks=%0d pixels=921600 words=%0d errors=0",checks,words);else $display("FAIL awb_capture errors=%0d",errors);$finish;
    end
endmodule
