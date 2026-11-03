`timescale 1ns/1ps
module tb_color_target_osd;
reg clk=0,rst=0,fs=0,de=0,v=1,o=0;always #5 clk=~clk;
reg [11:0] x=0,y=0;reg [7:0] count=4;reg [11:0] colors=12'h2d1,shapes=12'h451;
reg [79:0] areas={20'd10000,20'd12000,20'd16000,20'd20000};
reg [191:0] boxes={12'd900,12'd1172,12'd456,12'd636,12'd520,12'd668,12'd452,12'd600,12'd440,12'd732,12'd156,12'd316,12'd100,12'd300,12'd180,12'd380};
wire hit;wire [23:0] rgb;reg [7:0] gold_ch=0;reg [3:0] gold_row=0;wire [15:0] gold_glyph;
color_target_osd dut(.clk(clk),.rst_n(rst),.frame_start(fs),.de(de),.x(x),.y(y),.valid(v),.overflow(o),.target_count(count),.colors(colors),.shapes(shapes),.areas(areas),.boxes(boxes),.ov_valid(hit),.ov_rgb(rgb));
osd_char_lib reference_font(.I_char(gold_ch),.I_row(gold_row),.O_row_bits(gold_glyph));
integer errors=0,checks=0,a,b,slot,i,c,col,fp;reg test_done=0,expected_hit;reg [23:0] expected_rgb,paint;reg [527:0] title;
reg [11:0] bx0[0:3],bx1[0:3],by0[0:3],by1[0:3];reg [23:0] ink[0:3];
initial begin
 {bx0[0],bx1[0],by0[0],by1[0]}={12'd102,12'd305,12'd182,12'd385};ink[0]=24'hff3030;
 {bx0[1],bx1[1],by0[1],by1[1]}={12'd442,12'd737,12'd158,12'd321};ink[1]=24'hffff30;
 {bx0[2],bx1[2],by0[2],by1[2]}={12'd522,12'd673,12'd454,12'd605};ink[2]=24'h30ff30;
 {bx0[3],bx1[3],by0[3],by1[3]}={12'd902,12'd1177,12'd458,12'd641};ink[3]=24'hff3030;
 title="TARGETS:4 1 RED    SPHR 2 YELLOW CUBE 3 GREEN  SPHR 4 RED    CUBE ";
 repeat(4)@(negedge clk);rst=1;
 repeat(3)begin fs=1;@(negedge clk);fs=0;@(negedge clk);end
 de=1;
 fp=$fopen("targets-panel.ppm","w");
 if(fp==0)begin errors=errors+1;test_done=1;$display("FAIL target_osd image output");$finish;end
 $fdisplay(fp,"P3\n1280 720\n255");
 for(b=0;b<720;b=b+1)for(a=0;a<1280;a=a+1)begin
  x=a;y=b;expected_hit=0;expected_rgb=0;gold_ch=0;gold_row=0;col=0;
  for(i=3;i>=0;i=i-1)begin
   if(a>=bx0[i] && a<=bx1[i] && b>=by0[i] && b<=by1[i] &&
    (a<bx0[i]+2 || a>bx1[i]-2 || b<by0[i]+2 || b>by1[i]-2))begin expected_hit=1;expected_rgb=ink[i];end
   if(a>=bx0[i] && a<bx0[i]+16 && b>=by0[i] && b<by0[i]+16)begin gold_ch="1"+i;gold_row=b-by0[i];col=a-bx0[i];slot=i;end
  end
  if(a>=192 && a<1248 && b>=40 && b<56)begin
   c=(a-192)/16;gold_ch=title[(65-c)*8+:8];gold_row=b-40;col=(a-192)%16;
   slot=c<24?0:c<38?1:c<52?2:3;
  end
  #1;
  if(gold_ch!=0 && gold_glyph[15-col])begin expected_hit=1;expected_rgb=(b>=40 && b<56 && a<352)?24'h40ffff:ink[slot];end
  checks=checks+1;
  if(hit!==expected_hit || (expected_hit && rgb!==expected_rgb))begin errors=errors+1;if(errors<6)$display("FAIL target_osd pixel %0d,%0d hit%0d/%0d rgb%h/%h ch%h",a,b,hit,expected_hit,rgb,expected_rgb,gold_ch);end
  paint=hit?rgb:24'h606060;$fdisplay(fp,"%0d %0d %0d",paint[23:16],paint[15:8],paint[7:0]);
 end
 $fclose(fp);
 // Live changes cannot erase or replace a displayed frame halfway through it.
 v=0;o=1;count=0;colors=0;shapes=0;areas=0;boxes=0;x=102;y=200;#1;
 if(!hit || rgb!==ink[0])begin errors=errors+1;$display("FAIL target_osd cohort changed");end
 @(negedge clk);fs=1;@(negedge clk);fs=0;#1;
 if(hit)begin errors=errors+1;$display("FAIL target_osd clear");end
 x=320;y=40;#1;if(dut.character!=="E")begin errors=errors+1;$display("FAIL overflow E");end
 o=0;v=1;@(negedge clk);fs=1;@(negedge clk);fs=0;#1;
 if(dut.character!=="0")begin errors=errors+1;$display("FAIL empty count");end
 // Geometry-insufficient coloured texture remains an internal candidate.
 areas={4{20'd1000}};shapes={4{3'd5}};colors={4{3'd3}};count=4;
 boxes={144'd0,12'd100,12'd300,12'd180,12'd380};
 @(negedge clk);fs=1;@(negedge clk);fs=0;x=102;y=200;#1;
 if(hit || dut.present_s!=0 || dut.count_s!=0)begin errors=errors+1;$display("FAIL texture unknown displayed");end
 shapes[2:0]=2;
 repeat(3)begin @(negedge clk);fs=1;@(negedge clk);fs=0;end
 #1;
 if(dut.present_s!=1 || dut.count_s!=1)begin errors=errors+1;$display("FAIL known target among texture");end
 de=0;#1;if(hit)begin errors=errors+1;$display("FAIL blanking");end
 test_done=1;if(errors==0)$display("PASS color_target_osd pixels%0d fourlabels numberedboxes overflowE framecohort empty blanking",checks);else $display("FAIL color_target_osd errors%0d",errors);$finish;
end
endmodule
