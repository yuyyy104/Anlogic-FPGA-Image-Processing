`timescale 1ns/1ps
// Four largest colour-separated components from one captured palette frame.
// Palette IDs: 1 red, 2 yellow, 3 green. Blue/purple remain background.
// One CCL and one polygon processor are replayed serially; display pixels never wait.
module color_multitarget #(
 parameter H_ACTIVE=1280,V_ACTIVE=720,
 parameter MIN_COMPONENT_AREA=9,
 parameter MIN_BBOX=24
)(
 input clk,rst_n,input [23:0] rgb,input [4:0] timing,
 output reg valid,overflow,output reg [7:0] target_count,
 output reg [11:0] colors,shapes,output reg [79:0] areas,
 output reg [191:0] boxes
);
 localparam GW=H_ACTIVE/4,GH=V_ACTIVE/4,WORDS=(GW/8)*GH,AW=$clog2(WORDS);
 reg [23:0] palette[0:2*WORDS-1] /* fehdl force_ram=1, ram_style="bram_fast" */;
 reg [11:0] col,row;reg [19:0] pixel_count;reg cap_bank,scan_bank;
 reg [AW-1:0] cap_index;reg [20:0] pack;reg cap_active,cap_bad;
 reg [6:0] state;reg [2:0] pass_color;reg geometry_phase;
 reg scan_start;wire scan_ack,run_valid,row_end,scan_done,scan_overflow;
 wire [8:0] run_x0,run_x1;wire [7:0] run_y;
 wire [AW-1:0] read_address,scan_address;reg [23:0] read_data;
 reg [69:0] top[0:3];reg [2:0] selected;reg [1:0] insert_index;
 reg [9:0] total_count;reg bad;
 wire [11:0] x=timing[1]?12'd0:col,y=timing[1]?12'd0:row;
 wire sample=timing[2] && x[1:0]==0 && y[1:0]==0;
 wire [7:0] r=rgb[23:16],g=rgb[15:8],b=rgb[7:0];
 reg [2:0] color_id;
 function strong_channel;
 input [7:0] a,c;
 begin strong_channel={1'b0,a,1'b0}>={2'b0,c}+{1'b0,c,1'b0};end
 endfunction
  // Red is deliberately less restrictive than yellow/green: warm illumination
  // pulls G and B upward, while neutral highlights still fail the 4:3 test.
  function red_channel;
  input [7:0] a,c;
  begin red_channel=({2'b0,a}+{1'b0,a,1'b0})>={c,2'b00};end
  endfunction
 always @(*)begin
  color_id=0;
  // Yellow needs red and green together above blue, with a balanced R/G pair.
  if(r>=32 && g>=32 && {1'b0,r}>={1'b0,b}+9'd18 && {1'b0,g}>={1'b0,b}+9'd18 &&
          strong_channel(r,b) && strong_channel(g,b) &&
          {1'b0,r}<={1'b0,g}+({1'b0,g}>>1) && {1'b0,g}<={1'b0,r}+({1'b0,r}>>1))color_id=2;
  // G may rise under warm light, but B must stay clearly below red so magenta
  // and purple remain background rather than becoming red targets.
  else if(r>=18 && {1'b0,r}>={1'b0,g}+9'd8 && {1'b0,r}>={1'b0,b}+9'd8 &&
          red_channel(r,g) && strong_channel(r,b))color_id=1;
  // Green must dominate both red and blue, which keeps cyan from matching.
  else if(g>=24 && {1'b0,g}>={1'b0,r}+9'd10 && {1'b0,g}>={1'b0,b}+9'd10)color_id=3;
 end
 wire write_word=sample && x[4:2]==7 && cap_active;
 wire [AW:0] write_address=(cap_bank?WORDS:0)+cap_index;
 always @(posedge clk)begin
  if(write_word && (state==0 || cap_bank!=scan_bank))palette[write_address]<={color_id,pack};
  read_data<=palette[(scan_bank?WORDS:0)+read_address];
 end
 wire complete=timing[2] && timing[0] && x==H_ACTIVE-1 && y==V_ACTIVE-1 && pixel_count==H_ACTIVE*V_ACTIVE-1 && !cap_bad;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin col<=0;row<=0;pixel_count<=0;cap_bank<=0;cap_index<=0;pack<=0;cap_active<=0;cap_bad<=0;end
  else begin
   if(timing[1])begin pixel_count<=timing[2]?20'd1:20'd0;cap_index<=0;cap_active<=1;cap_bad<=0;pack<=0;end
   else if(timing[2])pixel_count<=pixel_count+1'b1;
   if(timing[2])begin col<=timing[0]?12'd0:x+1'b1;row<=timing[0]?y+1'b1:y;end
   if(sample)begin
    if(x[4:2]==7)cap_index<=cap_index+1'b1;
    else pack[x[4:2]*3+:3]<=color_id;
   end
   if(timing[2] && (x>=H_ACTIVE || y>=V_ACTIVE || timing[0]!=(x==H_ACTIVE-1)))cap_bad<=1;
   if(complete)begin cap_active<=0;if(state==0)cap_bank<=~cap_bank;end
  end
 end
 wire capture_abort=(timing[2] && (x>=H_ACTIVE || y>=V_ACTIVE || timing[0]!=(x==H_ACTIVE-1))) ||
  (timing[1] && cap_active && pixel_count!=H_ACTIVE*V_ACTIVE);
 reg [21:0] watchdog;
 wire timed_out=watchdog>=3*H_ACTIVE*V_ACTIVE;
 wire [7:0] component_mask;
 // Cancellation is sampled by the controller before state returns to idle.
 // Do not put capture_abort in this asynchronous reset: cap_active changes
 // on the first pixel while user is still high, creating a false reset pulse.
 wire processor_reset=rst_n && state!=0 && state!=1 && state!=30;
 wire [69:0] current=top[selected[1:0]];
 color_scan_runs #(.GRID_W(GW),.GRID_H(GH)) scanner(
  .clk(clk),.rst_n(processor_reset),.start(scan_start),.color_id(pass_color),.roi_enable(geometry_phase),
  .xmin(current[33:25]),.xmax(current[24:16]),.ymin(current[15:8]),.ymax(current[7:0]),
  .component_only(geometry_phase),.component_mask(component_mask),
  .read_address(scan_address),.read_data(read_data),.run_valid(run_valid),.run_x0(run_x0),.run_x1(run_x1),.run_y(run_y),
  .run_row_end(row_end),.run_ack(scan_ack),.done(scan_done),.overflow(scan_overflow));
 wire label_ack,label_done,label_valid,label_overflow;wire [7:0] label_count;
 wire [15:0] ar[0:3];wire [8:0] seed_x[0:3];wire [7:0] seed_y[0:3];wire [8:0] xmn[0:3],xmx[0:3];wire [7:0] ymn[0:3],ymx[0:3];
 shape_labels #(.A_MIN(MIN_COMPONENT_AREA),.MAXRUN(32),.MAXLBL(63)) labels(
  .clk(clk),.rst_n(processor_reset && !geometry_phase),.run_valid(run_valid),.run_x0(run_x0),.run_x1(run_x1),.run_y(run_y),
  .run_row_end(row_end),.run_ack(label_ack),.runs_overflow(scan_overflow),.scan_overflow(1'b0),.frame_end(scan_done),
  .frame_invalid(1'b0),.frame_global_change(1'b0),.global_change(),.result_done(label_done),.regions_valid(label_valid),
  .region_count(label_count),.regions_overflow(label_overflow),
  .r0_seed_x(seed_x[0]),.r1_seed_x(seed_x[1]),.r2_seed_x(seed_x[2]),.r3_seed_x(seed_x[3]),
  .r0_seed_y(seed_y[0]),.r1_seed_y(seed_y[1]),.r2_seed_y(seed_y[2]),.r3_seed_y(seed_y[3]),
  .r0_area(ar[0]),.r1_area(ar[1]),.r2_area(ar[2]),.r3_area(ar[3]),
  .r0_xmin(xmn[0]),.r0_xmax(xmx[0]),.r0_ymin(ymn[0]),.r0_ymax(ymx[0]),
  .r1_xmin(xmn[1]),.r1_xmax(xmx[1]),.r1_ymin(ymn[1]),.r1_ymax(ymx[1]),
  .r2_xmin(xmn[2]),.r2_xmax(xmx[2]),.r2_ymin(ymn[2]),.r2_ymax(ymx[2]),
  .r3_xmin(xmn[3]),.r3_xmax(xmx[3]),.r3_ymin(ymn[3]),.r3_ymax(ymx[3]));
 wire component_done,component_overflow,component_busy;wire [15:0] component_cells;reg component_start;
 color_component #(.GRID_W(GW),.GRID_H(GH)) component(
  .clk(clk),.rst_n(processor_reset),.start(component_start),.color_id(pass_color),.seed_x(current[69:61]),.seed_y(current[60:53]),
  .xmin(current[33:25]),.xmax(current[24:16]),.ymin(current[15:8]),.ymax(current[7:0]),
  .scan_address(scan_address),.read_address(read_address),.read_data(read_data),.component_mask(component_mask),
  .busy(component_busy),.done(component_done),.overflow(component_overflow),.cells(component_cells));
 reg row_valid;reg [8:0] row_left,row_right;reg [11:0] row_points;reg [15:0] inside_area;
 wire polygon_ready;wire [2:0] polygon_shape;
 wire [11:0] width_source={1'b0,current[24:16],2'b00}-{1'b0,current[33:25],2'b00}+12'd4;
 wire [11:0] height_source={2'd0,current[7:0],2'b00}-{2'd0,current[15:8],2'b00}+12'd4;
 shape_polygon #(.GRID_H(GH),.MIN_BBOX(MIN_BBOX)) polygon(
  .clk(clk),.rst_n(rst_n),.clear(state==0 || state==30 || capture_abort || timed_out),.row_write(geometry_phase && row_end),.row_valid(row_valid),.finish(scan_done && geometry_phase),
  .row_y(run_y),.row_left({1'b0,row_left,2'b00}),.row_right({1'b0,row_right,2'b00}),.row_points(row_points),
  .bbox_w(width_source),.bbox_h(height_source),.area({current[49:34],4'b0000}),.ready(polygon_ready),.shape(polygon_shape));
 assign scan_ack=geometry_phase?1'b1:label_ack;
 reg [11:0] result_shapes;integer k;reg [69:0] candidate;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=0;watchdog<=0;component_start<=0;pass_color<=1;geometry_phase<=0;scan_start<=0;scan_bank<=0;insert_index<=0;selected<=0;
   total_count<=0;bad<=0;valid<=0;overflow<=0;target_count<=0;colors<=0;shapes<=0;areas<=0;boxes<=0;result_shapes<=0;
   row_valid<=0;row_left<=0;row_right<=0;row_points<=0;inside_area<=0;
   for(k=0;k<4;k=k+1)top[k]<=0;
  end else begin
   scan_start<=0;component_start<=0;watchdog<=state==0?22'd0:watchdog+1'b1;
   if(geometry_phase && run_valid)begin
    if(!row_valid)row_left<=run_x0;
    row_right<=run_x1;row_points<=row_points+run_x1-run_x0+1'b1;row_valid<=1;
    inside_area<=inside_area+run_x1-run_x0+1'b1;
   end
   if(geometry_phase && row_end)begin row_valid<=0;row_points<=0;end
   if(capture_abort || timed_out)begin state<=0;valid<=0;overflow<=1;target_count<=0;colors<=0;shapes<=0;areas<=0;boxes<=0;end
   else case(state)
    0:if(complete)begin
     scan_bank<=cap_bank;pass_color<=1;geometry_phase<=0;state<=1;bad<=0;total_count<=0;result_shapes<=0;
     for(k=0;k<4;k=k+1)top[k]<=0;
    end
    1:state<=2;
    2:begin scan_start<=1;state<=3;end
    3:if(label_done)begin bad<=bad || !label_valid || label_overflow || total_count+{2'd0,label_count}>10'd255;total_count<=total_count+label_count;insert_index<=0;state<=4;end
    4:begin
     candidate={seed_x[insert_index],seed_y[insert_index],pass_color,ar[insert_index],xmn[insert_index],xmx[insert_index],ymn[insert_index],ymx[insert_index]};
     if(candidate[49:34]>top[0][49:34])begin top[3]<=top[2];top[2]<=top[1];top[1]<=top[0];top[0]<=candidate;end
     else if(candidate[49:34]>top[1][49:34])begin top[3]<=top[2];top[2]<=top[1];top[1]<=candidate;end
     else if(candidate[49:34]>top[2][49:34])begin top[3]<=top[2];top[2]<=candidate;end
     else if(candidate[49:34]>top[3][49:34])top[3]<=candidate;
     if(insert_index==3)begin
      if(pass_color==4)begin selected<=0;geometry_phase<=1;state<=29;end
      else begin pass_color<=pass_color+1'b1;state<=1;end
     end else insert_index<=insert_index+1'b1;
    end
    29:if(selected==4 || top[selected[1:0]][49:34]==0)state<=50;else begin pass_color<=top[selected[1:0]][52:50];state<=30;end
    30:begin row_valid<=0;row_points<=0;inside_area<=0;state<=31;end
    31:begin component_start<=1;state<=34;end
    34:if(component_done)begin
     if(component_overflow || component_cells!=current[49:34])begin bad<=1;selected<=selected+1'b1;state<=29;end
     else begin scan_start<=1;state<=32;end
    end
    32:if(scan_done)state<=33;
    33:if(polygon_ready)begin
     result_shapes[selected*3+:3]<=inside_area==current[49:34]?polygon_shape:3'd5;
     selected<=selected+1'b1;state<=29;
    end
    50:begin
     valid<=!bad;overflow<=bad;target_count<=bad?0:total_count>255?8'd255:total_count[7:0];
     for(k=0;k<4;k=k+1)begin
      colors[k*3+:3]<=bad?3'd0:top[k][52:50];shapes[k*3+:3]<=bad?3'd0:result_shapes[k*3+:3];
      areas[k*20+:20]<=bad?20'd0:{top[k][49:34],4'b0000};
      boxes[k*48+:48]<=bad?48'd0:{1'b0,top[k][33:25],2'b00,1'b0,top[k][24:16],2'b00,2'd0,top[k][15:8],2'b00,2'd0,top[k][7:0],2'b00};
     end
     state<=0;
    end
    default:state<=0;
   endcase
  end
 end
endmodule
