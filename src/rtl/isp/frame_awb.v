`timescale 1ns/1ps
// Four-lane pixel output remains continuous and two clocks deep.
module frame_awb #(
 parameter IMG_HEIGHT=720,IMG_WIDTH=1280,MIN_SAMPLES=128,
 parameter [49:0] REF_R_Q8={10'd254,10'd265,10'd273,10'd282,10'd211},
 parameter [49:0] REF_B_Q8={10'd254,10'd263,10'd266,10'd268,10'd234}
)(input I_clk,I_rst_n,I_tlast,I_tuser,I_tvalid,I_freeze,input [95:0] I_tdata,
 output I_tready,output reg O_tlast,O_tuser,O_tvalid,output reg [95:0] O_tdata,
 output reg [40:0] O_status,output reg O_status_valid,
 input O_tready,output reg O_frozen);
 localparam WORDS=IMG_HEIGHT*(IMG_WIDTH/4);
 localparam PW=IMG_WIDTH>=512?64:IMG_WIDTH/8<4?4:IMG_WIDTH/8;
 localparam PH=IMG_HEIGHT>=256?64:IMG_HEIGHT/8<2?2:IMG_HEIGHT/8;
 reg f1,f2,user_d;
 wire fs=I_tuser && !user_d;wire frozen_req=(f2===1'b1);
 assign I_tready=O_tready;
 always @(posedge I_clk or negedge I_rst_n)
  if(!I_rst_n)begin f1<=0;f2<=0;user_d<=0;end
  else begin f1<=I_freeze;f2<=f1;user_d<=I_tuser;end
 reg [9:0] input_col,input_row;reg previous_valid;
 wire [11:0] sx=fs?12'd3:{input_col,2'b11};wire [9:0] sy=fs?10'd0:input_row;
 always @(posedge I_clk or negedge I_rst_n)
  if(!I_rst_n)begin input_col<=0;input_row<=0;previous_valid<=0;end
  else if(fs)begin input_col<=I_tvalid?1:0;input_row<=0;previous_valid<=I_tvalid;end
  else begin previous_valid<=I_tvalid;if(I_tvalid)input_col<=input_col+1'b1;
   else if(previous_valid)begin input_col<=0;input_row<=input_row+1'b1;end end
 function in_patch;
  input [11:0] px;input [9:0] py;input integer cx,cy;
  begin in_patch=px>=cx-PW/2 && px<cx+PW/2 && py>=cy-PH/2 && py<cy+PH/2;end
 endfunction
 reg [2:0] point;
 always @(*)begin point=7;
  if(in_patch(sx,sy,IMG_WIDTH/2,IMG_HEIGHT/2))point=0;
  else if(in_patch(sx,sy,IMG_WIDTH/8,IMG_HEIGHT/8))point=1;
  else if(in_patch(sx,sy,IMG_WIDTH*7/8,IMG_HEIGHT/8))point=2;
  else if(in_patch(sx,sy,IMG_WIDTH/8,IMG_HEIGHT*7/8))point=3;
  else if(in_patch(sx,sy,IMG_WIDTH*7/8,IMG_HEIGHT*7/8))point=4;
 end
 wire [7:0] r=I_tdata[23:16],g=I_tdata[15:8],b=I_tdata[7:0];
 wire [7:0] hi=r>=g && r>=b?r:g>=b?g:b;
 wire [7:0] lo=r<=g && r<=b?r:g<=b?g:b;
 wire [7:0] mid=r>=g?(g>=b?g:r>=b?b:r):(r>=b?r:g>=b?b:g);
 wire [7:0] spread=hi-lo;
 wire eligible=point<5 && lo>=48 && g>=64 && hi<=248 && {spread,1'b0}<={1'b0,hi} &&
   {1'b0,hi,1'b0}<=({1'b0,mid,1'b0}+{2'b0,mid});
 reg [7:0] lr,lg,lb,wr_s,wg_s,wb_s;reg [2:0] point_lane,point_s;
 reg accept_lane,accept_s,valid_lane,valid_s,fs_lane,fs_s;
 always @(posedge I_clk or negedge I_rst_n)
  if(!I_rst_n)begin
   lr<=0;lg<=0;lb<=0;wr_s<=0;wg_s<=0;wb_s<=0;point_lane<=7;point_s<=7;
   accept_lane<=0;accept_s<=0;valid_lane<=0;valid_s<=0;fs_lane<=0;fs_s<=0;
  end else begin
   {lr,lg,lb,point_lane,accept_lane,valid_lane,fs_lane}<={r,g,b,point,eligible,I_tvalid,fs};
   {wr_s,wg_s,wb_s,point_s,accept_s,valid_s,fs_s}<={lr,lg,lb,point_lane,accept_lane,valid_lane,fs_lane};
  end
 // A valid patch has at most 1024 samples, each channel at most 248.
 reg [17:0] sums_r[0:4],sums_g[0:4],sums_b[0:4],saved_r[0:4],saved_g[0:4],saved_b[0:4];
 reg [10:0] counts[0:4],saved_count[0:4];reg [4:0] saved_ok,saved_bright,saved_single;
 reg [7:0] min_g[0:4],max_g[0:4];
 reg [18:0] words;reg started,input_valid_d,line_bad;reg [9:0] line_words,lines;
 wire frame_complete=started && words==WORDS && !line_bad &&
  ((lines==IMG_HEIGHT && !input_valid_d && line_words==0) ||
   (lines==IMG_HEIGHT-1 && input_valid_d && line_words==IMG_WIDTH/4));
 wire accept_word=valid_s && accept_s && point_s<5;
 reg [17:0] selected_r,selected_g,selected_b;
 reg [10:0] selected_count;
 integer bank;
 always @(*)begin
  selected_r=0;selected_g=0;selected_b=0;selected_count=0;
  for(bank=0;bank<5;bank=bank+1)if(point_s==bank)begin
   selected_r=sums_r[bank];selected_g=sums_g[bank];selected_b=sums_b[bank];selected_count=counts[bank];
  end
 end
 wire [17:0] added_r=selected_r+{10'd0,wr_s},added_g=selected_g+{10'd0,wg_s},added_b=selected_b+{10'd0,wb_s};
 wire [10:0] added_count=selected_count+11'd1;
 integer i;
 always @(posedge I_clk or negedge I_rst_n)begin
  if(!I_rst_n)begin words<=0;started<=0;input_valid_d<=0;line_bad<=0;line_words<=0;lines<=0;
   for(i=0;i<5;i=i+1)begin sums_r[i]<=0;sums_g[i]<=0;sums_b[i]<=0;counts[i]<=0;min_g[i]<=255;max_g[i]<=0;end
  end else if(fs_s)begin
   words<=valid_s?1:0;started<=1;input_valid_d<=valid_s;line_bad<=0;line_words<=valid_s?1:0;lines<=0;
   for(i=0;i<5;i=i+1)begin sums_r[i]<=0;sums_g[i]<=0;sums_b[i]<=0;counts[i]<=0;min_g[i]<=255;max_g[i]<=0;end
   for(i=0;i<5;i=i+1)if(accept_word && point_s==i)begin sums_r[i]<=wr_s;sums_g[i]<=wg_s;sums_b[i]<=wb_s;counts[i]<=1;min_g[i]<=wg_s;max_g[i]<=wg_s;end
  end else if(valid_s && started && words<=WORDS)begin
   input_valid_d<=1;line_words<=line_words+1'b1;words<=words+1'b1;
   if(line_words>=IMG_WIDTH/4)line_bad<=1;
   for(i=0;i<5;i=i+1)if(accept_word && point_s==i)begin sums_r[i]<=added_r;sums_g[i]<=added_g;
    sums_b[i]<=added_b;counts[i]<=added_count;
    if(wg_s<min_g[i])min_g[i]<=wg_s;if(wg_s>max_g[i])max_g[i]<=wg_s;end
  end else begin input_valid_d<=valid_s;
   if(!valid_s && input_valid_d && started)begin
    if(line_words!=IMG_WIDTH/4)line_bad<=1;line_words<=0;lines<=lines+1'b1;
   end
  end
 end
 reg [9:0] gain_r,gain_b,pending_r,pending_b;reg pending,sample_allowed;
 function [9:0] smooth;input [9:0] a,c;
  begin if(c>a+2)smooth=c-a>4?a+4:c;else if(a>c+2)smooth=a-c>4?a-4:c;else smooth=a;end
 endfunction
 wire apply_pending=fs && pending && !frozen_req && !O_frozen;
 wire [9:0] use_r=apply_pending?smooth(gain_r,pending_r):gain_r,use_b=apply_pending?smooth(gain_b,pending_b):gain_b;
 reg [3:0] state;reg [2:0] patch,anchor,peer,best_anchor,votes,best_votes,accepted_count;
 reg [9:0] ratios_r[0:4],ratios_b[0:4];reg [4:0] ratio_ok;
 reg [35:0] dividend,quot;reg [28:0] rem_r;reg [27:0] denom;reg [5:0] step;
 reg [29:0] multiplicand,product_r,product_b;reg [9:0] factor_r,factor_b;
 reg [10:0] best_distance;reg [12:0] fused_r,fused_b;
 reg [9:0] trusted_r,trusted_b,single_r,single_b;reg [2:0] single_patch;
 reg [1:0] single_streak;reg pending_single;reg [3:0] status_reason;
 reg [10:0] status_samples;reg [2:0] status_patch,status_votes;
 wire [28:0] trial={rem_r[27:0],dividend[35]};wire take=trial>={1'b0,denom};wire [35:0] q_next={quot[34:0],take};
 function [10:0] difference;input [9:0] a,c;
  begin difference=a>=c?{1'b0,a}-{1'b0,c}:{1'b0,c}-{1'b0,a};end
 endfunction
 wire [2:0] match_anchor=state==13?best_anchor:anchor;
 wire [4:0] usable=ratio_ok & ((|(ratio_ok & saved_bright))?saved_bright:5'b11111);
 wire matching=usable[peer] && difference(ratios_r[match_anchor],ratios_r[peer])<=24 && difference(ratios_b[match_anchor],ratios_b[peer])<=24;
 wire only_one=(usable!=0) && ((usable & (usable-5'd1))==0);
 wire single_close=single_patch==best_anchor && difference(single_r,ratios_r[best_anchor])<=8 && difference(single_b,ratios_b[best_anchor])<=8;
 wire single_bounded=difference(ratios_r[best_anchor],trusted_r)<=96 && difference(ratios_b[best_anchor],trusted_b)<=96;
 wire [2:0] votes_next=votes+matching;
 wire [10:0] distance=difference(ratios_r[anchor],gain_r)+difference(ratios_b[anchor],gain_b);
 wire fuse_match=matching;
 // A strong common colour change needs three agreeing regions. This keeps
 // weak observations conservative without blocking a well-covered start-up.
 wire common_cast=({pending_r,2'b00}>({2'd0,gain_r}<<2)+gain_r && {q_next[9:0],2'b00}>({2'd0,gain_b}<<2)+gain_b) ||
  ({pending_r,2'b00}<({2'd0,gain_r}<<1)+gain_r && {q_next[9:0],2'b00}<({2'd0,gain_b}<<1)+gain_b);
 integer n;
 always @(posedge I_clk or negedge I_rst_n)begin
  if(!I_rst_n)begin
   gain_r<=256;gain_b<=256;pending_r<=256;pending_b<=256;pending<=0;sample_allowed<=0;O_frozen<=0;
   state<=0;patch<=0;anchor<=0;peer<=0;best_anchor<=0;votes<=0;best_votes<=0;accepted_count<=0;
   dividend<=0;quot<=0;rem_r<=0;denom<=1;step<=0;multiplicand<=0;factor_r<=0;factor_b<=0;product_r<=0;product_b<=0;
   best_distance<=2047;fused_r<=0;fused_b<=0;saved_ok<=0;saved_bright<=0;saved_single<=0;ratio_ok<=0;
   trusted_r<=256;trusted_b<=256;single_r<=256;single_b<=256;single_patch<=7;single_streak<=0;pending_single<=0;
   status_reason<=2;status_samples<=0;status_patch<=7;status_votes<=0;O_status<=0;O_status_valid<=0;
   for(n=0;n<5;n=n+1)begin saved_r[n]<=0;saved_g[n]<=0;saved_b[n]<=0;saved_count[n]<=0;ratios_r[n]<=0;ratios_b[n]<=0;end
  end else if(fs)begin
   O_status<={use_r,use_b,status_samples,status_patch,status_votes,frozen_req?4'd6:status_reason};O_status_valid<=1;
   if(frozen_req || O_frozen)single_streak<=0;
   O_frozen<=frozen_req;pending<=0;state<=0;gain_r<=use_r;gain_b<=use_b;sample_allowed<=!frozen_req && !O_frozen;
  end else if(fs_s)begin
   O_status_valid<=0;
   if(sample_allowed && frame_complete)begin
    for(n=0;n<5;n=n+1)begin saved_r[n]<=sums_r[n];saved_g[n]<=sums_g[n];saved_b[n]<=sums_b[n];
     saved_count[n]<=counts[n];saved_ok[n]<=counts[n]>=MIN_SAMPLES && sums_r[n]!=0 && sums_b[n]!=0;
     saved_bright[n]<=sums_g[n]>=({counts[n],7'd0}+{1'b0,counts[n],6'd0});
     saved_single[n]<=counts[n]>=MIN_SAMPLES && counts[n]>=(PW*PH/8) && sums_g[n]>={counts[n],7'd0} && max_g[n]-min_g[n]<=24;end
    state<=1;patch<=0;ratio_ok<=0;best_votes<=0;best_distance<=2047;
   end else begin single_streak<=0;status_reason<=sample_allowed?5:6;status_samples<=0;status_votes<=0;status_patch<=7;end
  end else begin O_status_valid<=0;case(state)
   1:if(saved_ok[patch])begin multiplicand<={12'd0,saved_g[patch]};factor_r<=REF_R_Q8[patch*10+:10];factor_b<=REF_B_Q8[patch*10+:10];product_r<=0;product_b<=0;step<=0;state<=2;end else state<=5;
   2:begin if(factor_r[0])product_r<=product_r+multiplicand;if(factor_b[0])product_b<=product_b+multiplicand;
    factor_r<=factor_r>>1;factor_b<=factor_b>>1;multiplicand<=multiplicand<<1;
    if(step==9)state<=3;else step<=step+1'b1;
   end
   3:begin dividend<={6'd0,product_r};denom<={10'd0,saved_r[patch]};rem_r<=0;quot<=0;step<=0;state<=4;end
   4,6,10,12:begin dividend<=dividend<<1;rem_r<=take?trial-{1'b0,denom}:trial;quot<=q_next;
    if(step==35)begin
     if(state==4)begin ratios_r[patch]<=q_next>=128 && q_next<=512?q_next[9:0]:10'd0;state<=7;end
     else if(state==6)begin ratios_b[patch]<=q_next[9:0];ratio_ok[patch]<=q_next>=128 && q_next<=512 && ratios_r[patch]!=0;state<=5;end
     else if(state==10)begin pending_r<=q_next[9:0];state<=11;end
     else begin pending_b<=q_next[9:0];pending<=accepted_count>=3 || !common_cast;
      status_reason<=accepted_count>=3 || !common_cast?(pending_single?1:0):4;
      if(!pending_single && (accepted_count>=3 || !common_cast))begin trusted_r<=pending_r;trusted_b<=q_next[9:0];end
      state<=0;end
    end else step<=step+1'b1;
   end
   7:begin dividend<={6'd0,product_b};denom<={10'd0,saved_b[patch]};rem_r<=0;quot<=0;step<=0;state<=6;end
   5:if(patch==4)begin anchor<=0;peer<=0;votes<=0;state<=8;end else begin patch<=patch+1'b1;state<=1;end
   8:begin
    if(peer==4)begin
     if(usable[anchor] && (votes_next>best_votes || (votes_next==best_votes && distance<best_distance)))begin best_votes<=votes_next;best_anchor<=anchor;best_distance<=distance;end
     votes<=0;peer<=0;if(anchor==4)state<=9;else anchor<=anchor+1'b1;
    end else begin votes<=votes_next;peer<=peer+1'b1;end
   end
   9:begin
    status_samples<=best_votes!=0?saved_count[best_anchor]:0;status_patch<=best_votes!=0?best_anchor:7;status_votes<=best_votes;
    pending_single<=best_votes==1;
    if(best_votes>=2)begin single_streak<=0;peer<=0;fused_r<=0;fused_b<=0;accepted_count<=0;state<=13;end
    else if(best_votes==1 && only_one && saved_single[best_anchor] && single_bounded)begin
     single_r<=ratios_r[best_anchor];single_b<=ratios_b[best_anchor];single_patch<=best_anchor;
     single_streak<=single_close?(single_streak==3?3:single_streak+1'b1):1;
     if(single_close && single_streak>=2)begin peer<=0;fused_r<=0;fused_b<=0;accepted_count<=0;state<=13;end
     else begin status_reason<=3;state<=0;end
    end else begin single_streak<=0;status_reason<=best_votes==0?2:7;state<=0;end
   end
   13:begin if(fuse_match)begin fused_r<=fused_r+ratios_r[peer];fused_b<=fused_b+ratios_b[peer];accepted_count<=accepted_count+1'b1;end
    if(peer==4)state<=14;else peer<=peer+1'b1;
   end
   14:begin dividend<={23'd0,fused_r};denom<={25'd0,accepted_count};rem_r<=0;quot<=0;step<=0;state<=10;end
   11:begin dividend<={23'd0,fused_b};denom<={25'd0,accepted_count};rem_r<=0;quot<=0;step<=0;state<=12;end
   default:state<=0;
  endcase end
 end
 reg [17:0] rp[0:3],bp[0:3];reg [7:0] gp[0:3];reg valid_1,user_1,last_1;integer j;
 function [7:0] clip;input [17:0] p;reg [18:0] rounded;
  begin rounded={1'b0,p}+128;clip=rounded[18:8]>255?255:rounded[15:8];end
 endfunction
 always @(posedge I_clk or negedge I_rst_n)
  if(!I_rst_n)begin valid_1<=0;user_1<=0;last_1<=0;O_tvalid<=0;O_tuser<=0;O_tlast<=0;O_tdata<=0;
   for(j=0;j<4;j=j+1)begin rp[j]<=0;bp[j]<=0;gp[j]<=0;end
  end else begin valid_1<=I_tvalid;user_1<=I_tuser;last_1<=I_tlast;O_tvalid<=valid_1;O_tuser<=user_1;O_tlast<=last_1;O_tdata<=0;
   for(j=0;j<4;j=j+1)begin
    if(I_tvalid)begin rp[j]<=I_tdata[j*24+16+:8]*use_r;bp[j]<=I_tdata[j*24+:8]*use_b;gp[j]<=I_tdata[j*24+8+:8];end
    if(valid_1)O_tdata[j*24+:24]<={clip(rp[j]),gp[j],clip(bp[j])};
   end
  end
endmodule
