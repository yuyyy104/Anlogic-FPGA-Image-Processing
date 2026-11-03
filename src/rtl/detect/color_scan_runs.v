`timescale 1ns/1ps
// Replay one captured palette frame with backpressure. Colour-ID zero is background.
module color_scan_runs #(parameter GRID_W=320,GRID_H=180)(
 input clk,rst_n,start,input [2:0] color_id,input roi_enable,
 input component_only,input [7:0] component_mask,
 input [8:0] xmin,xmax,input [7:0] ymin,ymax,
 output wire [$clog2((GRID_W/8)*GRID_H)-1:0] read_address,input [23:0] read_data,
 output wire run_valid,output wire [8:0] run_x0,run_x1,output wire [7:0] run_y,
 output wire run_row_end,input run_ack,output reg done,overflow
);
 localparam AW=$clog2((GRID_W/8)*GRID_H),GROUPS=GRID_W/8;
 localparam IDLE=0,RD=1,WAIT=2,SAMPLE=3,EMIT=4,ROWEND=5,GAP=6;
 reg [2:0] state,bit_index;reg [5:0] group_index;reg [7:0] row;
 reg [AW-1:0] row_base;reg [23:0] pixels;
 reg open_run,pending;reg [8:0] open_x,p_x0,p_x1;reg [7:0] p_y,row_runs;
 reg p_end;
 wire [8:0] x={group_index,3'b000}+{6'd0,bit_index};
 wire at_end=x==GRID_W-1;
 wire on_cell=pixels[bit_index*3+:3]==color_id && color_id!=0 &&
              (!component_only || component_mask[bit_index]) &&
              (!roi_enable || (x>=xmin && x<=xmax && row>=ymin && row<=ymax));
 wire close_run=(at_end && on_cell) || (!on_cell && open_run);
 assign read_address=row_base+group_index;
 assign run_valid=pending;assign run_x0=p_x0;assign run_x1=p_x1;assign run_y=state==ROWEND?row:p_y;
 assign run_row_end=(state==ROWEND) && !pending;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=IDLE;bit_index<=0;group_index<=0;row<=0;row_base<=0;pixels<=0;
   open_run<=0;pending<=0;open_x<=0;p_x0<=0;p_x1<=0;p_y<=0;p_end<=0;row_runs<=0;done<=0;overflow<=0;
  end else begin
   done<=0;
   case(state)
    IDLE:if(start)begin row<=0;row_base<=0;group_index<=0;bit_index<=0;open_run<=0;pending<=0;row_runs<=0;overflow<=0;state<=RD;end
    RD:state<=WAIT;
    WAIT:begin pixels<=read_data;bit_index<=0;state<=SAMPLE;end
    SAMPLE:begin
     if(close_run)begin
      pending<=1;p_x0<=open_run?open_x:x;p_x1<=on_cell?x:x-1'b1;p_y<=row;p_end<=at_end;open_run<=0;state<=EMIT;
     end else begin
      if(on_cell && !open_run)begin open_run<=1;open_x<=x;end
      if(at_end)state<=ROWEND;
      else if(bit_index==7)begin group_index<=group_index+1'b1;state<=RD;end
      else bit_index<=bit_index+1'b1;
     end
    end
    EMIT:if(run_ack)begin
     pending<=0;row_runs<=row_runs+1'b1;
     if(p_end)state<=GAP;
     else if(bit_index==7)begin group_index<=group_index+1'b1;state<=RD;end
     else begin bit_index<=bit_index+1'b1;state<=SAMPLE;end
    end
    GAP:state<=ROWEND;
    ROWEND:if(run_ack)begin
     if(row_runs>32)overflow<=1;
     row_runs<=0;open_run<=0;
     if(row==GRID_H-1)begin done<=1;state<=IDLE;end
     else begin row<=row+1'b1;row_base<=row_base+GROUPS;group_index<=0;bit_index<=0;state<=RD;end
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
