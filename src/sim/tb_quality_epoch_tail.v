`timescale 1ns/1ps
// No row or frame blanking: changed quality frames must not consume the old
// filter tail after the early epoch reset, and must accept their first pixel.
module tb_quality_epoch_tail;
    reg clk=0,rst_n=0,test_done=0;always #5 clk=~clk;
    reg [4:0] t=0;reg [23:0] rgb=0,r1=0,r2=0;reg enable=0;
    wire [4:0] ot;wire rd;
    always @(posedge clk)begin r1<=rgb;r2<=r1;end
    video_display_pipe #(.IMAGE_WIDTH(128),.V_ACTIVE(16)) dut(
        .clk(clk),.rst_n(rst_n),.read_rgb(r2),.request_timing(t),
        .i_mode(4'd0),.i_thresh(8'd96),.i_use_btn(1'b1),.i_denoise(enable),
        .read_en(rd),.timing_out(ot)
    );
    integer errors=0,checks=0,guarded=0,firsts=0,f,y,x,k,shape_checks=0;
    reg [31:0] shape_expected[0:13];
    integer expected_index;
    reg shape_edge;
    reg [4:0] tq[0:21];
    always @(posedge clk)begin
        shape_edge=dut.g_single_target.u_detect.de && dut.g_single_target.u_detect.user;
        if(!rst_n)for(k=0;k<22;k=k+1)tq[k]<=0;
        else begin
            tq[0]<=t;for(k=1;k<22;k=k+1)tq[k]<=tq[k-1];
            if(dut.g_single_target.u_detect.de && dut.g_single_target.u_detect.user)firsts=firsts+1;
            if(dut.detect_rst_n && !dut.detect_armed && dut.quality_timing[2] && !dut.quality_timing[1])begin
                guarded=guarded+1;
                if(dut.detect_de || dut.g_single_target.u_detect.col!=0)begin errors=errors+1;$display("FAIL old quality tail accepted");end
            end
        end
        #1;
        if(rst_n&&!test_done)begin checks=checks+1;
            if(ot!==tq[21]||rd!==t[2])begin errors=errors+1;$display("FAIL epoch timing/read");end
            if(shape_edge&&(firsts==6||firsts==7))begin
                shape_checks=shape_checks+1;
                // Full-image matrix/filter/mask reference is generated from
                // the stimulus, without sampling DUT state or fitting offsets.
                expected_index=(firsts-6)*7;
                if(!dut.det_valid||dut.det_cls!=shape_expected[expected_index]||
                   dut.det_area!=shape_expected[expected_index+1]||
                   dut.det_xmin!=shape_expected[expected_index+2]||dut.det_xmax!=shape_expected[expected_index+3]||
                   dut.det_ymin!=shape_expected[expected_index+4]||dut.det_ymax!=shape_expected[expected_index+5]||
                   dut.det_reason!=shape_expected[expected_index+6])begin
                    errors=errors+1;$display("FAIL filtered P3 valid=%b cls=%0d area=%0d bbox=%0d,%0d,%0d,%0d",
                        dut.det_valid,dut.det_cls,dut.det_area,dut.det_xmin,dut.det_xmax,dut.det_ymin,dut.det_ymax);
                end
            end
        end
    end
    initial begin
        $readmemh("D:/codex_project/FPGA_competiton/src/sim/fixtures/shape_recall/quality_epoch_expected.mem",shape_expected);
        repeat(5)@(negedge clk);rst_n=1;
        for(f=0;f<7;f=f+1)begin
            enable=f<4 ? f%2 : 1;
            for(y=0;y<16;y=y+1)for(x=0;x<128;x=x+1)begin
                @(negedge clk);t={2'b01,1'b1,(x==0&&y==0),(x==127)};
                if(f<4)rgb=f%2 ? 24'h303030 : 24'hff2020;
                else if(f<=5&&y>=4&&y<12&&x>=32&&x<96)
                    rgb=f==4&&y==7&&x==64 ? 24'hffffff : 24'hff2020;
                else rgb=24'h303030;
            end
            // The first four frames deliberately have no blanking to exercise
            // epoch tails. Positive P3 classification uses its documented
            // vertical blanking budget for frame-end serial multiplication.
            if(f>=3)repeat(32)begin @(negedge clk);t=0;rgb=0;end
        end
        @(negedge clk);t=0;repeat(24)@(negedge clk);
        if(firsts!=7||guarded<3||shape_checks!=2)begin errors=errors+1;
            $display("FAIL tail coverage first=%0d guard=%0d shape=%0d",firsts,guarded,shape_checks);end
        test_done=1;
        if(errors==0)$display("PASS quality_epoch_tail checks=%0d firsts=%0d guarded=%0d filtered_shapes=%0d",checks,firsts,guarded,shape_checks);
        else $display("FAIL quality_epoch_tail errors=%0d",errors);
        $finish;
    end
endmodule
