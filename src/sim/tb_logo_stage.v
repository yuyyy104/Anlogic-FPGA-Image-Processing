`timescale 1ns/1ps
module tb_logo_stage;
 localparam W=200,H=170,LAT=3;
 reg clk=0,rst=0;always #5 clk=~clk;
 reg [4:0] req=0;reg [23:0] source=0;
 wire hv,hh,hd,rd;wire [23:0] rgb;
 hdmi_mixer #(.IMG_WIDTH(W),.IMG_HEIGHT(H)) dut(
  .I_clk(clk),.I_rst_n(rst),.I_video_vsync(req[4]),.I_video_hsync(req[3]),.I_video_de(req[2]),
  .I_video_user(req[1]),.I_video_last(req[0]),.I_video_rd_data(source),.I_debug_status(4'b1111),
  .I_denoise(1'b0),.I_lock(1'b0),.I_wb_frozen(1'b0),.I_cal_enable(1'b0),.I_cal_valid(1'b0),
  .I_cal_regions_in(120'd0),.I_cal_regions_out(120'd0),.I_cal_regions_clip_in(65'd0),.I_cal_regions_clip_out(65'd0),
  .I_cal_regions_valid(1'b0),.I_cal_rgb(24'd0),.I_cal_clipped(13'd0),.I_det_reason(3'd0),.I_mode(4'd0),.I_thresh(8'd96),
  .I_det_valid(1'b0),.I_det_cls(2'd0),.I_det_area(20'd0),.I_det_xmin(12'd0),.I_det_xmax(12'd0),.I_det_ymin(12'd0),.I_det_ymax(12'd0),
  .I_mv_valid(1'b0),.I_ae_src_auto(1'b0),.I_mv_count(8'd0),.I_mv_overflow(1'b0),.I_mv_global_change(1'b0),
  .I_mv_r0(48'd0),.I_mv_r1(48'd0),.I_mv_r2(48'd0),.I_mv_r3(48'd0),.I_lat_ms(16'd0),.I_lat_valid(1'b0),.I_lat_tgl(1'b0),
  .O_video_rd_en(rd),.O_hdmi_vsync(hv),.O_hdmi_hsync(hh),.O_hdmi_de(hd),.O_hdmi_data(rgb),.O_out_first_tgl());
 reg [24:0] logo[0:25599];reg [4:0] tq[0:LAT-1];reg [23:0] eq[0:LAT-1];
 integer xx=0,yy=0,k,f,x,y,errors=0,checks=0,pixels=0,opaque=0;reg test_done=0;reg [24:0] lp;
 always @(posedge clk)begin
  if(!rst)for(k=0;k<LAT;k=k+1)begin tq[k]<=0;eq[k]<=0;end
  else begin
   lp=(req[2] && xx<160 && yy<160)?logo[yy*160+xx]:25'd0;
   tq[0]<=req;eq[0]<=lp[24]?lp[23:0]:source;
   for(k=1;k<LAT;k=k+1)begin tq[k]<=tq[k-1];eq[k]<=eq[k-1];end
   #1;checks=checks+1;
   if(rd!==req[2] || {hv,hh,hd}!==tq[LAT-1][4:2])begin errors=errors+1;if(errors<5)$display("FAIL logo timing3");end
   if(hd)begin
    pixels=pixels+1;
    if(rgb!==eq[LAT-1])begin errors=errors+1;if(errors<5)$display("FAIL logo pixel%0d got%h expected%h",pixels,rgb,eq[LAT-1]);end
   end
  end
 end
 initial begin
  $readmemh("D:/codex_project/FPGA_competiton/src/sim/fixtures/logo_stage/pixels.mem",logo);
  for(k=0;k<25600;k=k+1)if(logo[k][24])opaque=opaque+1;
  repeat(4)@(negedge clk);rst=1;
  for(f=0;f<2;f=f+1)begin
   for(y=0;y<H;y=y+1)begin
    for(x=0;x<192;x=x+1)begin
     @(negedge clk);{xx,yy}={x,y};source={x[7:0],y[7:0],8'h45};req={2'b00,1'b1,(x==0 && y==0),(x==191)};
    end
    if(y%2==0)begin @(negedge clk);{req,source}=29'd0;repeat(2)@(negedge clk);end
   end
   @(negedge clk);{req,source}=29'd0;repeat(f==0?0:12)@(negedge clk);
  end
  repeat(4)@(negedge clk);
  test_done=1;if(errors==0)$display("PASS logo_stage twoframes every160x160 logo plus32pixelborder zeroblank_alternate_rows frame_restart timing3 checks%0d pixels%0d opaque_per_frame%0d",checks,pixels,opaque);
  else $display("FAIL logo_stage errors%0d",errors);$finish;
 end
endmodule
