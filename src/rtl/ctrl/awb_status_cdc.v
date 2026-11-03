`timescale 1ns/1ps
// Source payload stays immutable until destination acknowledges its capture.
module awb_status_cdc(
 input src_clk,dst_clk,rst_n,src_valid,input [40:0] src_data,
 output reg [40:0] dst_data
);
 reg [40:0] held,data_1,data_2;
 reg req,ack,ack_1,ack_2,req_1,req_2,req_3;
 always @(posedge src_clk or negedge rst_n)
  if(!rst_n)begin held<=0;req<=0;ack_1<=0;ack_2<=0;end
  else begin
   ack_1<=ack;ack_2<=ack_1;
   if(src_valid && ack_2==req)begin held<=src_data;req<=~req;end
  end
 always @(posedge dst_clk or negedge rst_n)
  if(!rst_n)begin data_1<=0;data_2<=0;dst_data<=0;req_1<=0;req_2<=0;req_3<=0;ack<=0;end
  else begin
   data_1<=held;data_2<=data_1;req_1<=req;req_2<=req_1;req_3<=req_2;
   if(req_3!=ack)begin dst_data<=data_2;ack<=req_3;end
  end
endmodule
