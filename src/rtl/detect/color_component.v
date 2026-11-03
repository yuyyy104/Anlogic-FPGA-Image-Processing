`timescale 1ns/1ps
// Reconstruct the selected connected component by a bounded FIFO flood fill.
// The visited bitmap is byte-packed and reused for all four targets.
module color_component #(parameter GRID_W=320,GRID_H=180,QUEUE_DEPTH=1024)(
 input clk,rst_n,start,input [2:0] color_id,input [8:0] seed_x,xmin,xmax,
 input [7:0] seed_y,ymin,ymax,
 input [$clog2((GRID_W/8)*GRID_H)-1:0] scan_address,
 output wire [$clog2((GRID_W/8)*GRID_H)-1:0] read_address,
 input [23:0] read_data,output wire [7:0] component_mask,
 output reg busy,done,overflow,output reg [15:0] cells
);
 localparam WORDS=(GRID_W/8)*GRID_H,AW=$clog2(WORDS),QW=$clog2(QUEUE_DEPTH);
 reg [7:0] visited[0:WORDS-1] /* fehdl force_ram=1, ram_style="bram_fast" */;
 reg [16:0] queue[0:QUEUE_DEPTH-1] /* fehdl force_ram=1, ram_style="bram_fast" */;
 reg [7:0] visit_data;reg [16:0] queue_data;
 reg [AW-1:0] address,clear_address,write_address;reg [7:0] write_data;
 reg write_visit,write_queue;reg [QW-1:0] head,tail,queue_write_address;
 reg [16:0] queue_write_data;reg [QW:0] pending;
 reg [8:0] cx,nx;reg [7:0] cy,ny;reg [3:0] neighbor;
 reg [3:0] state;reg seed_check;
 assign read_address=busy?address:scan_address;
 assign component_mask=visit_data;
 always @(posedge clk)begin
  visit_data<=visited[read_address];queue_data<=queue[head];
  if(write_visit)visited[write_address]<=write_data;
  if(write_queue)queue[queue_write_address]<=queue_write_data;
 end
 reg [8:0] tx;reg [7:0] ty;reg inside;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=0;busy<=0;done<=0;overflow<=0;cells<=0;address<=0;clear_address<=0;write_address<=0;write_data<=0;
   write_visit<=0;write_queue<=0;head<=0;tail<=0;queue_write_address<=0;queue_write_data<=0;pending<=0;
   cx<=0;cy<=0;nx<=0;ny<=0;neighbor<=0;seed_check<=0;
  end else begin
   write_visit<=0;write_queue<=0;done<=0;
   case(state)
    0:if(start)begin busy<=1;overflow<=0;cells<=0;head<=0;tail<=0;pending<=0;clear_address<=0;state<=1;end
    1:begin
     write_visit<=1;write_address<=clear_address;write_data<=0;
     if(clear_address==WORDS-1)begin nx<=seed_x;ny<=seed_y;address<=seed_y*(GRID_W/8)+(seed_x>>3);seed_check<=1;state<=2;end
     else clear_address<=clear_address+1'b1;
    end
    2:state<=3;
    3:begin
     if(read_data[(nx[2:0]*3)+:3]==color_id && !visit_data[nx[2:0]])begin
      if(pending==QUEUE_DEPTH)begin overflow<=1;state<=10;end
      else begin
       write_visit<=1;write_address<=address;write_data<=visit_data|(8'd1<<nx[2:0]);
       write_queue<=1;queue_write_address<=tail;queue_write_data<={nx,ny};tail<=tail+1'b1;pending<=pending+1'b1;cells<=cells+1'b1;
       state<=seed_check?4:7;
      end
     end else if(seed_check)begin overflow<=1;state<=10;end
     else state<=7;
     seed_check<=0;
    end
    4:if(pending==0)state<=10;else state<=5;
    5:state<=6;
    6:begin cx<=queue_data[16:8];cy<=queue_data[7:0];head<=head+1'b1;pending<=pending-1'b1;neighbor<=0;state<=7;end
    7:begin
     tx=cx;ty=cy;inside=1;
     case(neighbor)
      0:if(cx==xmin)inside=0;else tx=cx-1'b1;
      1:if(cx==xmax)inside=0;else tx=cx+1'b1;
      2:if(cy==ymin)inside=0;else ty=cy-1'b1;
      3:if(cy==ymax)inside=0;else ty=cy+1'b1;
      4:if(cx==xmin || cy==ymin)inside=0;else begin tx=cx-1'b1;ty=cy-1'b1;end
      5:if(cx==xmax || cy==ymin)inside=0;else begin tx=cx+1'b1;ty=cy-1'b1;end
      6:if(cx==xmin || cy==ymax)inside=0;else begin tx=cx-1'b1;ty=cy+1'b1;end
      7:if(cx==xmax || cy==ymax)inside=0;else begin tx=cx+1'b1;ty=cy+1'b1;end
      default:inside=0;
     endcase
     if(neighbor==8)state<=4;
     else begin
      neighbor<=neighbor+1'b1;
      if(inside)begin nx<=tx;ny<=ty;address<=ty*(GRID_W/8)+(tx>>3);state<=2;end
     end
    end
    10:begin busy<=0;done<=1;state<=0;end
    default:state<=0;
   endcase
  end
 end
endmodule
