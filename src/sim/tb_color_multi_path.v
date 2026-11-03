`timescale 1ns/1ps
module tb_color_multi_path;
localparam W=512,H=256,LAT=32;
reg clk=0,rst=0;always #5 clk=~clk;
reg [23:0] src=0,s1=0,s2=0;reg [4:0] req=0;reg dn=0;reg [3:0] mode=0;
wire hv,hh,hd,rd;wire [23:0] out;
p3_display_glue dut(.S_hdmi_pixel_clk(clk),.S_hdmi_rst_n(rst),.S_video_rd_data(s2),
 .S_hdmi_vsync(req[4]),.S_hdmi_hsync(req[3]),.S_hdmi_de(req[2]),.S_hdmi_user(req[1]),.S_hdmi_last(req[0]),
 .S_preproc_mode(mode),.S_preproc_thresh(8'd96),.S_hdmi_debug_status(4'b1111),.S_denoise_stable(dn),
 .S_cal_stable(1'b0),.S_lock_stable(1'b1),.S_awb_frozen(1'b1),.S_hdmi_window_rd_en(rd),
 .S_hdmi_out_vsync(hv),.S_hdmi_out_hsync(hh),.S_hdmi_out_de(hd),.S_hdmi_out_data(out));
always @(posedge clk){s1,s2}<={src,s1};
`include "D:/codex_project/FPGA_competiton/src/sim/fixtures/color_multi_path/expected.vh"
reg [23:0] image[0:W*H-1],gold0[0:W*H-1],gold1[0:W*H-1];
reg [4:0] tq[0:LAT-1];integer xq[0:LAT-1],yq[0:LAT-1],fq[0:LAT-1];
integer x=0,y=0,f=0,k,s,errors=0,checks=0,quality_pixels=0,box_pixels=0;reg test_done=0;
integer dx=0,dy=0,df=0;
reg [25:0] e;reg [47:0] box;reg [23:0] expected_rgb;integer a,b;reg hit;
reg pre_valid,pre_over;reg [7:0] pre_count;reg [11:0] pre_colors,pre_shapes;reg [79:0] pre_areas;reg [191:0] pre_boxes;
reg expected_valid=0,expected_over=0;reg [7:0] expected_count=0;reg [11:0] expected_colors=0,expected_shapes=0;reg [79:0] expected_areas=0;reg [191:0] expected_boxes=0;
reg [3:0] expected_present;integer expected_display_count;
always @(posedge clk)begin
 if(!rst)for(k=0;k<LAT;k=k+1){tq[k],xq[k],yq[k],fq[k]}<=101'd0;
 else begin
  {pre_valid,pre_over,pre_count,pre_colors,pre_shapes,pre_areas,pre_boxes}={dut.S_targets_valid,dut.S_targets_overflow,dut.S_targets_count,dut.S_targets_colors,dut.S_targets_shapes,dut.S_targets_areas,dut.S_targets_boxes};
  {tq[0],xq[0],yq[0],fq[0]}<={req,dx,dy,df};
  for(k=1;k<LAT;k=k+1){tq[k],xq[k],yq[k],fq[k]}<={tq[k-1],xq[k-1],yq[k-1],fq[k-1]};
  #1;checks=checks+1;
  if(rd!==req[2] || {hv,hh,hd}!==tq[LAT-1][4:2])begin errors=errors+1;if(errors<5)$display("FAIL multi_path timing32");end
  if(dut.u_video_display_pipe.quality_timing!==tq[14])begin errors=errors+1;if(errors<5)$display("FAIL quality timing15");end
  if(tq[14][2] && fq[14]<4)begin
   quality_pixels=quality_pixels+1;expected_rgb=fq[14]<2?gold0[yq[14]*W+xq[14]]:gold1[yq[14]*W+xq[14]];
   if(dut.u_video_display_pipe.quality_rgb!==expected_rgb)begin errors=errors+1;if(errors<5)$display("FAIL quality source f%0d xy%0d,%0d %h/%h",fq[14],xq[14],yq[14],dut.u_video_display_pipe.quality_rgb,expected_rgb);end
   if(errors>=5)begin test_done=1;$finish;end
  end
  // Snapshot belongs to stage2's first pixel, one cycle before HDMI output.
  if(tq[LAT-2][2] && tq[LAT-2][1])begin
   {expected_valid,expected_over,expected_count,expected_colors,expected_shapes,expected_areas,expected_boxes}={pre_valid,pre_over,pre_count,pre_colors,pre_shapes,pre_areas,pre_boxes};
  end
  expected_display_count=0;
  for(s=0;s<4;s=s+1)begin
   expected_present[s]=expected_areas[s*20+:20]!=0 && expected_shapes[s*3+:3]>=1 && expected_shapes[s*3+:3]<=4;
   if(expected_present[s])expected_display_count=expected_display_count+1;
  end
  if({dut.u_hdmi_mixer.g_targets.u_targets_osd.valid_s,dut.u_hdmi_mixer.g_targets.u_targets_osd.overflow_s,dut.u_hdmi_mixer.g_targets.u_targets_osd.count_s,dut.u_hdmi_mixer.g_targets.u_targets_osd.colors_s,dut.u_hdmi_mixer.g_targets.u_targets_osd.shapes_s,dut.u_hdmi_mixer.g_targets.u_targets_osd.present_s,dut.u_hdmi_mixer.g_targets.u_targets_osd.boxes_s}!=={expected_valid,expected_over,expected_display_count[7:0],expected_colors,expected_shapes,expected_present,expected_boxes})begin errors=errors+1;if(errors<5)$display("FAIL multi_path snapshot cohort");end
  if(hd && fq[LAT-1]==1 && yq[LAT-1]>=160)begin
   for(s=0;s<4;s=s+1)begin
    box=path_box(0,s);a=xq[LAT-1];b=yq[LAT-1];
    // Bottom sides avoid status, calibration, logo and number badges.
    if(b==box[11:0]+5 && a>=box[47:36]+18 && a<=box[35:24]+5)begin
     box_pixels=box_pixels+1;e=path_result(0,s);
     case(e[25:23])1:expected_rgb=24'hff3030;2:expected_rgb=24'h30ff30;3:expected_rgb=24'h4080ff;4:expected_rgb=24'hffff30;endcase
     if(out!==expected_rgb)begin errors=errors+1;if(errors<5)$display("FAIL actual fourbox slot%0d xy%0d,%0d %h/%h",s,a,b,out,expected_rgb);end
    end
   end
  end
 end
end
task result_check;input integer d;begin
 checks=checks+1;if(!dut.S_targets_valid || dut.S_targets_overflow || dut.S_targets_count!=4)begin errors=errors+1;$display("FAIL actual result valid count%0d",dut.S_targets_count);end
 for(s=0;s<4;s=s+1)begin e=path_result(d,s);
  if(dut.S_targets_colors[s*3+:3]!==e[25:23] || dut.S_targets_shapes[s*3+:3]!==e[22:20] || dut.S_targets_areas[s*20+:20]!==e[19:0] || dut.S_targets_boxes[s*48+:48]!==path_box(d,s))begin errors=errors+1;$display("FAIL actual component slot%0d color%0d shape%0d box%h/%h",s,dut.S_targets_colors[s*3+:3],dut.S_targets_shapes[s*3+:3],dut.S_targets_boxes[s*48+:48],path_box(d,s));end
 end
end endtask
initial begin
 $readmemh("D:/codex_project/FPGA_competiton/src/sim/fixtures/color_shapes/four_colours.mem",image);
 $readmemh("D:/codex_project/FPGA_competiton/src/sim/fixtures/color_multi_path/quality-dn0.mem",gold0);
 $readmemh("D:/codex_project/FPGA_competiton/src/sim/fixtures/color_multi_path/quality-dn1.mem",gold1);
 repeat(5)@(negedge clk);rst=1;
 for(f=0;f<7;f=f+1)begin
  dn=f>=2;mode=f==2 || f==3?5:0;
  // Consumer-only injections after the real algorithm checks: a live payload
  // changes at raw frame start while preceding output pixels are still in flight.
  if(f==4)begin force dut.S_targets_valid=1;force dut.S_targets_overflow=0;force dut.S_targets_count=1;force dut.S_targets_colors=1;force dut.S_targets_shapes=2;force dut.S_targets_areas=1000;force dut.S_targets_boxes={144'd0,12'd40,12'd128,12'd220,12'd252};end
  if(f==5)begin force dut.S_targets_valid=0;force dut.S_targets_count=0;force dut.S_targets_colors=0;force dut.S_targets_shapes=0;force dut.S_targets_areas=0;force dut.S_targets_boxes=0;end
  if(f==6)begin force dut.S_targets_valid=1;force dut.S_targets_count=1;force dut.S_targets_colors=4;force dut.S_targets_shapes=5;force dut.S_targets_areas=1000;force dut.S_targets_boxes={144'd0,12'd40,12'd128,12'd220,12'd252};end
  for(y=0;y<H;y=y+1)for(x=0;x<W;x=x+1)begin
   @(negedge clk);req={2'b00,1'b1,(x==0 && y==0),(x==W-1)};{dx,dy,df}={x,y,f};src=f<4?image[y*W+x]:24'h606060;
  end
  if(f<4)begin
   @(negedge clk);req=0;src=0;repeat(230000)@(negedge clk);result_check(f>=2);
  end
 end
 @(negedge clk);req=0;repeat(40)@(negedge clk);
 if(box_pixels==0)begin errors=errors+1;$display("FAIL fourbox consumer unobserved");end
 test_done=1;if(errors==0)$display("PASS color_multi_path checks%0d quality_pixels%0d box_pixels%0d actual_top MULTI1 LSC1 DN0_DN1 MODE0_MODE5 packet fourbox timing32 zero_blank snapshot",checks,quality_pixels,box_pixels);else $display("FAIL color_multi_path errors%0d",errors);$finish;
end
endmodule
