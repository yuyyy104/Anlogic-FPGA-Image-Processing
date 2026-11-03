/*******************************MILIANKE*******************************
*Company : MiLianKe Electronic Technology Co., Ltd.
*WebSite:https://www.milianke.com
*TechWeb:https://www.uisrc.com
*tmall-shop:https://milianke.tmall.com
*jd-shop:https://milianke.jd.com
*taobao-shop1: https://milianke.taobao.com
*Create Date: 2023/03/23
*Module Name:
*File Name:
*Description: 
*The reference demo provided by Milianke is only used for learning. 
*We cannot ensure that the demo itself is free of bugs, so users 
*should be responsible for the technical problems and consequences
*caused by the use of their own products.
*Copyright: Copyright (c) MiLianKe
*All rights reserved.
*Revision: 1.0
*Signal description
*1) I_ input
*2) O_ output
*3) IO_ input output
*4) S_ system internal signal
*5) _n activ low
*6) _dg debug signal 
*7) _r delay or register
*8) _s state mechine
*********************************************************************/
/*********ae_set �ֶ��������AE ***********
--�汾��1.0
*********************************************************************/

module ae_set(
    input wire I_clk,I_rst,
    input wire I_hold,
    input wire [1:0] I_ag_toggle,
    input wire I_ae_cfg_done,I_cam_cfg_done,I_auto_active,
    input wire [15:0] I_cur_ae,I_cur_ag,
    output wire O_manual_evt,O_ae_req,
    output wire [15:0] O_ae,O_ag
);
    // First-stage names are selected exactly by the existing targeted SDC.
    reg [3:0] r_button_0=0,r_button_1=0,r_button_d=0;
    wire [1:0] ag_evt=r_button_1[3:2]^r_button_d[3:2];
    wire net_ag_evt=^ag_evt;
    reg ag_pending=0;
    reg [15:0] r_ae_set=1991,r_ag_set=16;
    reg [15:0] r_ae=1990,r_ag=17;
    reg r_ae_req=0,in_flight=0,seen_busy=0;
    wire desired_changed=(r_ae_set!=r_ae)||(r_ag_set!=r_ag);
    reg hold_1=0,hold_2=0;
    wire held=(hold_2===1'b1);
    assign O_manual_evt=!held && (net_ag_evt || ag_pending ||
                        (!I_auto_active && (in_flight || desired_changed)));
    wire [15:0] ag_base=(I_auto_active && !ag_pending)?I_cur_ag:r_ag_set;
    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst) begin
            r_button_0<=0;r_button_1<=0;r_button_d<=0;ag_pending<=0;hold_1<=0;hold_2<=0;
            r_ae_set<=1991;r_ag_set<=16;
        end else begin
            r_button_0<={I_ag_toggle,2'b00};
            r_button_1<=r_button_0;r_button_d<=r_button_1;
            hold_1<=I_hold;hold_2<=hold_1;
            // Busy AUTO may delay transfer. Accumulate user steps in the target,
            // independently of the immutable snapshot currently being sent.
            if(held || (I_auto_active && !ag_pending)) begin
                r_ae_set<=I_cur_ae;r_ag_set<=I_cur_ag;
            end
            if(held) ag_pending<=0;
            else if(net_ag_evt) begin
                ag_pending<=1;
                if(ag_evt[0]) r_ag_set<=(ag_base>16)?ag_base-1'b1:16;
                else r_ag_set<=(ag_base<176)?ag_base+1'b1:176;
            end else if(!I_auto_active) ag_pending<=0;
        end
    end
    assign O_ae=r_ae;assign O_ag=r_ag;assign O_ae_req=r_ae_req;
    always @(posedge I_clk or posedge I_rst) begin
        if(I_rst) begin
            r_ae_req<=0;r_ae<=1990;r_ag<=17;in_flight<=0;seen_busy<=0;
        end else if(held || I_auto_active) begin
            r_ae<=I_cur_ae;r_ag<=I_cur_ag;r_ae_req<=0;in_flight<=0;seen_busy<=0;
        end else begin
            r_ae_req<=0;
            // Do not infer acceptance from an idle level: wait for busy then done.
            // New steps may update the target throughout this transaction.
            if(in_flight) begin
                if(!I_ae_cfg_done) seen_busy<=1;
                else if(seen_busy) begin in_flight<=0;seen_busy<=0;end
            end else if(desired_changed && I_cam_cfg_done && I_ae_cfg_done) begin
                r_ae<=r_ae_set;r_ag<=r_ag_set;r_ae_req<=1;
                in_flight<=1;seen_busy<=0;
            end
        end
    end
endmodule
