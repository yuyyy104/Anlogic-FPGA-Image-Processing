`timescale 1ns/1ps
module color_regions_osd #(parameter H_ACTIVE=1280,V_ACTIVE=720,POINTS=5)(
 input clk,rst_n,frame_start,de,input [11:0] x,y,
 input lock_exposure,freeze_wb,enable,sample_valid,
 input [POINTS*24-1:0] mean_in,mean_out,input [POINTS*13-1:0] clip_in,clip_out,
 input [40:0] awb_status,
 input [11:0] shape_w,shape_h,input [2:0] reason,
 output wire hit,output wire [23:0] color
);
 localparam FIELDS=POINTS*8+2+(POINTS==9?3:0),ADDR_W=$clog2(FIELDS);
 reg [40:0] awb_s;
 reg lock_s,wb_s,en_s,valid_s;reg [2:0] why_s;
 reg [12:0] values[0:FIELDS-1];
 reg [15:0] digits[0:(1<<ADDR_W)-1]; // synthesis ram_style=dram
 reg [FIELDS-1:0] digit_written;
 reg [28:0] shift_r,next_r;reg [3:0] steps;reg [ADDR_W-1:0] field;
 integer k,j;
 always @(*) begin
  next_r=shift_r;
  for(k=13;k<29;k=k+4) if(next_r[k+:4]>=5) next_r[k+:4]=next_r[k+:4]+3;
  next_r=next_r<<1;
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   {awb_s,lock_s,wb_s,en_s,valid_s,why_s,shift_r,steps,field,digit_written}<=0;
   for(j=0;j<FIELDS;j=j+1) values[j]<=0;
  end else if(frame_start) begin
   awb_s<=awb_status;lock_s<=lock_exposure;wb_s<=freeze_wb;en_s<=enable;valid_s<=sample_valid;why_s<=reason;
   for(j=0;j<POINTS;j=j+1) begin
    values[j*8]<={5'd0,mean_in[j*24+16+:8]};values[j*8+1]<={5'd0,mean_in[j*24+8+:8]};values[j*8+2]<={5'd0,mean_in[j*24+:8]};
    values[j*8+3]<={5'd0,mean_out[j*24+16+:8]};values[j*8+4]<={5'd0,mean_out[j*24+8+:8]};values[j*8+5]<={5'd0,mean_out[j*24+:8]};
    values[j*8+6]<=clip_in[j*13+:13];values[j*8+7]<=clip_out[j*13+:13];
   end
   values[POINTS*8]<={1'b0,shape_w};values[POINTS*8+1]<={1'b0,shape_h};
   if(POINTS==9)begin values[POINTS*8+2]<={3'd0,awb_status[40:31]};values[POINTS*8+3]<={3'd0,awb_status[30:21]};values[POINTS*8+4]<={2'd0,awb_status[20:10]};end
   shift_r<={21'd0,mean_in[23:16]};steps<=13;field<=0;
  end else if(steps!=0) begin
   shift_r<=next_r;steps<=steps-1'b1;
   if(steps==1) begin
    digit_written[field]<=1;
    if(field<FIELDS-1) begin field<=field+1'b1;shift_r<={16'd0,values[field+1'b1]};steps<=13;end
   end
  end
 end
 // No memory reset: unwritten fields read zero, while frame updates retain
 // each previous digit until its existing thirteen-clock conversion completes.
 always @(posedge clk)if(rst_n && !frame_start && steps==1)digits[field]<=next_r[28:13];
 wire header=y>=88 && y<104,tail=y>=112+POINTS*24 && y<128+POINTS*24;
 wire diagnostic=POINTS==9 && y>=136+POINTS*24 && y<152+POINTS*24;
 reg row_hit;reg [3:0] r;reg [11:0] ly;
 integer row_index;
 always @(*) begin
  row_hit=0;r=0;ly=0;
  for(row_index=0;row_index<POINTS;row_index=row_index+1)
   if(y>=112+row_index*24 && y<128+row_index*24)begin row_hit=1;r=row_index;ly=y-(112+row_index*24);end
  if(header)ly=y-88;
  if(tail)ly=y-(112+POINTS*24);
  if(diagnostic)ly=y-(136+POINTS*24);
 end
 wire [11:0] lx=x-192;wire [5:0] cell_idx=lx[9:4];reg [7:0] ch;
 reg digit_hit;reg [ADDR_W-1:0] digit_address;reg [1:0] digit_position;
 function [7:0] digit;
 input [15:0] v;input [1:0] pos;
 begin case(pos) 0:digit=48+v[15:12];1:digit=48+v[11:8];2:digit=48+v[7:4];default:digit=48+v[3:0];endcase end
 endfunction
 always @(*) begin
  ch=32;digit_hit=0;digit_address=0;digit_position=0;
  if(header) case(cell_idx)
   0:ch="L";1:ch="O";2:ch="C";3:ch="K";4:ch=":";5:ch=lock_s?"1":"0";
   7:ch="W";8:ch="B";9:ch=":";10:ch=wb_s?"1":"0";
   12:ch="C";13:ch="A";14:ch="L";15:ch=":";16:ch=en_s?"1":"0";
   20:ch="R";21:ch="G";22:ch="B";24:ch="I";25:ch="N";26:ch="/";27:ch="O";28:ch="U";29:ch="T";
   31:ch="C";32:ch="L";33:ch="I";34:ch="P";
  endcase
  else if(row_hit) begin
   case(cell_idx)
    0:ch=r==0?"C":(r==1 || r==2 || r==5)?"T":(r==6 || r==7)?"M":"B";1:ch=r==0?"E":(r==1 || r==3 || r==6)?"L":(r==2 || r==4 || r==7)?"R":"C";2:ch=r==0?"N":32;
    4:ch="I";5:ch="N";6:ch=":";10:ch="/";14:ch="/";
    18:ch="O";19:ch="U";20:ch="T";24:ch="/";28:ch="/";
    33:ch="C";34:ch=":";39:ch="/";45:ch=valid_s?"O":"W";46:ch=valid_s?"K":"T";
   endcase
   if(cell_idx>=7 && cell_idx<=9)begin digit_hit=1;digit_address=r*8+0;digit_position=cell_idx-6;end
   else if(cell_idx>=11 && cell_idx<=13)begin digit_hit=1;digit_address=r*8+1;digit_position=cell_idx-10;end
   else if(cell_idx>=15 && cell_idx<=17)begin digit_hit=1;digit_address=r*8+2;digit_position=cell_idx-14;end
   else if(cell_idx>=21 && cell_idx<=23)begin digit_hit=1;digit_address=r*8+3;digit_position=cell_idx-20;end
   else if(cell_idx>=25 && cell_idx<=27)begin digit_hit=1;digit_address=r*8+4;digit_position=cell_idx-24;end
   else if(cell_idx>=29 && cell_idx<=31)begin digit_hit=1;digit_address=r*8+5;digit_position=cell_idx-28;end
   else if(cell_idx>=35 && cell_idx<=38)begin digit_hit=1;digit_address=r*8+6;digit_position=cell_idx-35;end
   else if(cell_idx>=40 && cell_idx<=43)begin digit_hit=1;digit_address=r*8+7;digit_position=cell_idx-40;end
  end else if(tail) begin
   case(cell_idx) 0:ch="W";1:ch=":";7:ch="H";8:ch=":";14:ch="W";15:ch="H";16:ch="Y";17:ch=":";18:ch=48+why_s;endcase
   if(cell_idx>=2 && cell_idx<=5)begin digit_hit=1;digit_address=POINTS*8;digit_position=cell_idx-2;end
   else if(cell_idx>=9 && cell_idx<=12)begin digit_hit=1;digit_address=POINTS*8+1;digit_position=cell_idx-9;end
  end
  if(diagnostic)begin
   case(cell_idx)0:ch="G";1:ch="R";2:ch=":";8:ch="G";9:ch="B";10:ch=":";16:ch="N";17:ch=":";23:ch="P";24:ch=":";25:ch=48+awb_s[9:7];27:ch="V";28:ch=":";29:ch=48+awb_s[6:4];31:ch="S";32:ch=":";33:ch=48+awb_s[3:0];endcase
   if(cell_idx>=3 && cell_idx<=6)begin digit_hit=1;digit_address=POINTS*8+2;digit_position=cell_idx-3;end
   else if(cell_idx>=11 && cell_idx<=14)begin digit_hit=1;digit_address=POINTS*8+3;digit_position=cell_idx-11;end
   else if(cell_idx>=18 && cell_idx<=21)begin digit_hit=1;digit_address=POINTS*8+4;digit_position=cell_idx-18;end
  end
  if(digit_hit)ch=row_hit && !valid_s?"-":digit(digit_written[digit_address]?digits[digit_address]:16'd0,digit_position);
 end
 wire [15:0] glyph;osd_char_lib font(.I_char(ch),.I_row(ly[3:0]),.O_row_bits(glyph));
 wire text_region=de && x>=192 && x<960 && (header || (en_s && (row_hit || tail || diagnostic)));
 wire [POINTS-1:0] box;
 genvar g;
 generate for(g=0;g<POINTS;g=g+1) begin : boxes
  localparam X0=(g==1 || g==3 || g==6?H_ACTIVE/8:g==2 || g==4 || g==7?H_ACTIVE*7/8:H_ACTIVE/2)-29;
  localparam Y0=(g==1 || g==2 || g==5?V_ACTIVE/8:g==3 || g==4 || g==8?V_ACTIVE*7/8:V_ACTIVE/2)-29;
  assign box[g]=de && en_s && x>=X0 && x<=X0+63 && y>=Y0 && y<=Y0+63 && (x==X0 || x==X0+63 || y==Y0 || y==Y0+63);
 end endgenerate
 assign hit=text_region || (|box);
 assign color=text_region?(glyph[15-lx[3:0]]?24'h00ffff:24'h101820):24'h00ffff;
endmodule
