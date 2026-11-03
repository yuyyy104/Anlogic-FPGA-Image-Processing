`timescale 1ns/1ps
// Frame-snapshot top-four boxes and readable colour/object names.
// A colour/object class must persist for CONFIRM_FRAMES before it is shown.
// Confirmation is independent of the top-four slot order, so a changing area
// ranking cannot reset an otherwise stable target.
module color_target_osd #(
 parameter H_ACTIVE=1280,V_ACTIVE=720,
 parameter integer CONFIRM_FRAMES=1,
 parameter integer MIN_BOX=1
)(
 input clk,rst_n,frame_start,de,input [11:0] x,y,
 input valid,overflow,input [7:0] target_count,input [11:0] colors,shapes,
 input [79:0] areas,input [191:0] boxes,
 output reg ov_valid,output reg [23:0] ov_rgb
);
 reg valid_s,overflow_s;reg [7:0] count_s;reg [11:0] colors_s,shapes_s;
 reg [3:0] present_s;reg [191:0] boxes_s;
 reg [3:0] recognized,candidate_ok;
 reg [2:0] class_count[0:7];
 reg [7:0] class_seen;
 integer ci,si,class_idx;
 always @(*)begin
  candidate_ok=0;recognized=0;class_seen=0;
  for(ci=0;ci<4;ci=ci+1)begin
   if(valid && !overflow && |areas[ci*20+:20] &&
      shapes[ci*3+:3]>=1 && shapes[ci*3+:3]<=2 &&
      boxes[ci*48+36+:12]-boxes[ci*48+24+:12]+1>=MIN_BOX &&
      boxes[ci*48+12+:12]-boxes[ci*48+:12]+1>=MIN_BOX)candidate_ok[ci]=1;
   if(candidate_ok[ci])begin
    class_idx=(colors[ci*3+:3]-1)*2+(shapes[ci*3+:3]-1);
    class_seen[class_idx]=1;
    if(class_count[class_idx]>=CONFIRM_FRAMES-1)recognized[ci]=1;
   end
  end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   valid_s<=0;overflow_s<=0;count_s<=0;colors_s<=0;shapes_s<=0;present_s<=0;boxes_s<=0;
   for(si=0;si<8;si=si+1)class_count[si]<=0;
  end else if(frame_start)begin valid_s<=valid;overflow_s<=overflow;
   count_s<={7'd0,recognized[0]}+{7'd0,recognized[1]}+{7'd0,recognized[2]}+{7'd0,recognized[3]};
   colors_s<=colors;shapes_s<=shapes;
   present_s<=recognized;boxes_s<=boxes;
   for(si=0;si<8;si=si+1)begin
    if(!class_seen[si])class_count[si]<=0;
    else if(class_count[si]!=3'd7)class_count[si]<=class_count[si]+1'b1;
   end
  end
 end
 function [23:0] color_rgb;
 input [2:0] color_id;
 begin case(color_id)1:color_rgb=24'hff3030;2:color_rgb=24'hffff30;3:color_rgb=24'h30ff30;default:color_rgb=24'hff40ff;endcase end
 endfunction
 function [7:0] color_character;
 input [2:0] c;input [3:0] index;
 reg [47:0] word;
 begin case(c)1:word="RED   ";2:word="YELLOW";3:word="GREEN ";default:word="      ";endcase
 color_character=word[(5-index)*8+:8];end
 endfunction
 function [7:0] shape_character;
 input [2:0] c;input [2:0] index;
 reg [31:0] word;
 begin case(c)1:word="SPHR";2:word="CUBE";default:word="UNKN";endcase
 shape_character=word[(3-index)*8+:8];end
 endfunction
 wire text_zone=x>=192 && x<1248 && y>=40 && y<56;
 wire [6:0] cidx=(x-12'd192)>>4;
 reg [7:0] character;reg [23:0] text_color,box_color;
 reg box_hit,in_text;integer i,slot,local_cell;reg [11:0] x0,x1,y0,y1;
 reg [3:0] glyph_row,glyph_column;
 wire [15:0] glyph;
 osd_char_lib font(.I_char(character),.I_row(glyph_row),.O_row_bits(glyph));
 always @(*)begin
  character=0;text_color=24'h40ffff;slot=0;local_cell=0;in_text=text_zone;
  glyph_row=y-12'd40;glyph_column=x[3:0];
  if(text_zone)begin
   case(cidx)
    0:character="T";1:character="A";2:character="R";3:character="G";4:character="E";5:character="T";6:character="S";7:character=":";
    8:character=overflow_s?"E":valid_s?"0"+(count_s>4?8'd4:count_s):"-";
    default:begin
     if(cidx>=10)begin
      if(cidx<24)begin slot=0;local_cell=cidx-10;end
      else if(cidx<38)begin slot=1;local_cell=cidx-24;end
      else if(cidx<52)begin slot=2;local_cell=cidx-38;end
      else begin slot=3;local_cell=cidx-52;end
      if(valid_s && present_s[slot])begin
       text_color=color_rgb(colors_s[slot*3+:3]);
       if(local_cell==0)character="1"+slot;
       else if(local_cell>=2 && local_cell<8)character=color_character(colors_s[slot*3+:3],local_cell-2);
       else if(local_cell>=9 && local_cell<13)character=shape_character(shapes_s[slot*3+:3],local_cell-9);
      end
     end
    end
   endcase
  end
  box_hit=0;box_color=0;x0=0;x1=0;y0=0;y1=0;
  for(i=3;i>=0;i=i-1)begin
   x0=boxes_s[i*48+36+:12]+12'd2;x1=boxes_s[i*48+24+:12]+12'd5;
   y0=boxes_s[i*48+12+:12]+12'd2;y1=boxes_s[i*48+:12]+12'd5;
   if(x1>=H_ACTIVE)x1=H_ACTIVE-1;if(y1>=V_ACTIVE)y1=V_ACTIVE-1;
   if(valid_s && present_s[i] && x>=x0 && x<=x1 && y>=y0 && y<=y1 &&
    (x<x0+2 || x>x1-2 || y<y0+2 || y>y1-2))begin box_hit=1;box_color=color_rgb(colors_s[i*3+:3]);end
   if(!text_zone && valid_s && present_s[i] && x>=x0 && x<x0+16 && y>=y0 && y<y0+16)begin
    character="1"+i;glyph_row=y-y0;glyph_column=x-x0;in_text=1;text_color=color_rgb(colors_s[i*3+:3]);
   end
  end
  ov_valid=rst_n && de && (box_hit || (in_text && glyph[15-glyph_column]));
  ov_rgb=in_text && glyph[15-glyph_column]?text_color:box_color;
 end
endmodule
