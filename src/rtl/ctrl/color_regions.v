`timescale 1ns/1ps
// Accumulate directly across four complete frames; no duplicate per-frame adders.
// Five or nine 64x64 patches, common coordinates/frame accounting for simultaneous taps.
// Low slice = centre, then TL/TR/BL/BR. Four complete frames per publication.
module color_regions #(parameter H_ACTIVE=1280,V_ACTIVE=720,POINTS=5)(
 input clk,rst_n,enable,input [4:0] timing,input [23:0] rgb_in,rgb_out,
 output reg [POINTS*24-1:0] mean_in,mean_out,output reg [POINTS*13-1:0] clip_in,clip_out,
 output reg valid
);
 reg [11:0] col,row;
 wire [11:0] x=timing[1]?12'd0:col,y=timing[1]?12'd0:row;
 wire [POINTS-1:0] inside_patch;
 reg active,started;reg [19:0] nr;reg [1:0] frames;
 reg [12:0] count[0:POINTS-1];
 reg [21:0] tr[0:POINTS*2-1],tg[0:POINTS*2-1],tb[0:POINTS*2-1];reg [14:0] tc[0:POINTS*2-1];
 // These raster sizes give disjoint patches. Share arithmetic while keeping
 // each patch's storage and its original write enable; small rasters retain
 // independent additions because their patches can overlap.
 localparam COMMON_TOTALS=H_ACTIVE>=256 && V_ACTIVE>=256;
 reg [3:0] selected_patch;
 integer s;
 always @(*)begin
  selected_patch=0;
  for(s=0;s<POINTS;s=s+1)if(inside_patch[s])selected_patch=s;
 end
 wire [12:0] count_next=count[selected_patch]+13'd1;
 wire [21:0] ri_next=tr[selected_patch]+{14'd0,rgb_in[23:16]};
 wire [21:0] gi_next=tg[selected_patch]+{14'd0,rgb_in[15:8]};
 wire [21:0] bi_next=tb[selected_patch]+{14'd0,rgb_in[7:0]};
 wire [21:0] ro_next=tr[selected_patch+POINTS]+{14'd0,rgb_out[23:16]};
 wire [21:0] go_next=tg[selected_patch+POINTS]+{14'd0,rgb_out[15:8]};
 wire [21:0] bo_next=tb[selected_patch+POINTS]+{14'd0,rgb_out[7:0]};
 wire [14:0] ci_next=tc[selected_patch]+15'd1;
 wire [14:0] co_next=tc[selected_patch+POINTS]+15'd1;
 wire [23:0] p[0:POINTS*2-1];wire [POINTS*2-1:0] clipped;
 reg complete;integer c;
 always @(*)begin complete=nr==H_ACTIVE*V_ACTIVE;for(c=0;c<POINTS;c=c+1)if(count[c]!=4096)complete=0;end
 genvar g;
 generate for(g=0;g<POINTS;g=g+1) begin : regions
  localparam X0=(g==1 || g==3 || g==6?H_ACTIVE/8:g==2 || g==4 || g==7?H_ACTIVE*7/8:H_ACTIVE/2)-32;
  localparam Y0=(g==1 || g==2 || g==5?V_ACTIVE/8:g==3 || g==4 || g==8?V_ACTIVE*7/8:V_ACTIVE/2)-32;
  assign inside_patch[g]=x>=X0 && x<X0+64 && y>=Y0 && y<Y0+64;
 end
 for(g=0;g<POINTS*2;g=g+1)begin : totals
  assign p[g]=g<POINTS?rgb_in:rgb_out;
  assign clipped[g]=p[g][23:16]>=250 || p[g][15:8]>=250 || p[g][7:0]>=250;
 end endgenerate
 integer j;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   {col,row,active,started,nr,frames,mean_in,mean_out,clip_in,clip_out,valid}<=0;
   for(j=0;j<POINTS;j=j+1)count[j]<=0;
   for(j=0;j<POINTS*2;j=j+1)begin {tr[j],tg[j],tb[j],tc[j]}<=0;end
  end else begin
   if(timing[2])begin col<=timing[0]?12'd0:x+1'b1;row<=timing[0]?y+1'b1:y;end
   if(timing[2] && timing[1])begin
    active<=enable;started<=1;nr<=1;
    // Production 1280x720 and the 512x256 integration raster exclude (0,0).
    for(j=0;j<POINTS;j=j+1)count[j]<=0;
    if(!enable || !active || !started || !complete)begin
     frames<=0;valid<=0;
     for(j=0;j<POINTS*2;j=j+1){tr[j],tg[j],tb[j],tc[j]}<=0;
    end else if(frames==3)begin
     valid<=1;frames<=0;
     for(j=0;j<POINTS;j=j+1)begin
      mean_in[j*24+:24]<={tr[j][21:14],tg[j][21:14],tb[j][21:14]};
      mean_out[j*24+:24]<={tr[j+POINTS][21:14],tg[j+POINTS][21:14],tb[j+POINTS][21:14]};
      clip_in[j*13+:13]<=tc[j][14:2];clip_out[j*13+:13]<=tc[j+POINTS][14:2];
     end
     for(j=0;j<POINTS*2;j=j+1){tr[j],tg[j],tb[j],tc[j]}<=0;
    end else begin
     frames<=frames+1'b1;
    end
   end else if(timing[2] && started && nr<H_ACTIVE*V_ACTIVE+1)begin
    nr<=nr+1'b1;
    if(COMMON_TOTALS)begin
     for(j=0;j<POINTS;j=j+1)if(active && inside_patch[j])begin
      count[j]<=count_next;
      {tr[j],tg[j],tb[j]}<={ri_next,gi_next,bi_next};
      {tr[j+POINTS],tg[j+POINTS],tb[j+POINTS]}<={ro_next,go_next,bo_next};
      if(clipped[0])tc[j]<=ci_next;
      if(clipped[POINTS])tc[j+POINTS]<=co_next;
     end
    end else begin
     for(j=0;j<POINTS;j=j+1)if(active && inside_patch[j])count[j]<=count[j]+1'b1;
     for(j=0;j<POINTS*2;j=j+1)if(active && inside_patch[j%POINTS])begin
      {tr[j],tg[j],tb[j]}<={tr[j]+{14'd0,p[j][23:16]},tg[j]+{14'd0,p[j][15:8]},tb[j]+{14'd0,p[j][7:0]}};
      if(clipped[j])tc[j]<=tc[j]+1'b1;
     end
    end
   end
  end
 end
endmodule
