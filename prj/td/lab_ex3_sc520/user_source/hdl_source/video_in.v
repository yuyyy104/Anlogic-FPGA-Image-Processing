

module video_in (
    input wire         I_rst_n,

    input wire         I_camera_clk,
    input wire         I_camera_frame_start,
    input wire         I_camera_valid,
    input wire[127:0]  I_camera_data,
    input wire         I_mipi_rx_error,

    input wire         I_ddr_clk,

    input wire         I_display_pause,
    input wire         I_video_out_rd_busy,
    output wire        O_video_in_wr_busy,
    output reg[1:0]    O_video_out_rp,     ///读指针

    // P5: frame identity / latency taps (read-only, ddr domain).
    // O_frame_start is the 1-cycle frame-start pulse. O_wr_slot names the new write slot at
    // that edge only; wp then advances, so an observer must retain the pre-edge slot for beats.
    output wire        O_frame_start,
    output wire[1:0]   O_wr_slot,
    output reg         O_capture_fault, // sticky camera-domain staging loss; reset to recover

    output reg         O_ddr_user_wr_en,
    output reg[24:0]   O_ddr_user_addr,
    output wire[127:0] O_ddr_user_wr_data,
    input wire         I_ddr_user_ready
);

    wire        S_fifo_rst;
    wire        S_fifo_full;
    // ISP user accompanies its first data, while the legacy FIFO reset arrives through DDR
    // several cycles later and stays asserted for eight camera cycles. Stage those words until
    // reset has completed instead of writing a frame header that will immediately be erased.
    reg [127:0] frame_head[0:31];
    reg [4:0] head_wp,head_rp;
    reg [5:0] head_count;
    reg head_hold,head_reset_seen,head_seen;
    reg head_rst1,head_rst2,head_rst3;
    wire head_pop = !head_hold && (head_count!=0) && !S_fifo_full && !I_camera_frame_start;
    wire head_push = head_seen && I_camera_valid && ((head_count<32) || head_pop);
    wire head_store = I_camera_frame_start ? I_camera_valid : head_push;
    wire [4:0] head_store_addr = I_camera_frame_start ? 5'd0 : head_wp;
    // Single, unreset memory write port; reset only the pointers/occupancy, not stored pixels.
    always @(posedge I_camera_clk)
        if(I_rst_n && head_store) frame_head[head_store_addr] <= I_camera_data;
    always @(posedge I_camera_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            head_wp<=0;head_rp<=0;head_count<=0;
            head_hold<=1;head_reset_seen<=0;head_seen<=0;
            head_rst1<=0;head_rst2<=0;head_rst3<=0;
            O_capture_fault<=0;
        end else begin
            head_rst1<=S_fifo_rst;head_rst2<=head_rst1;head_rst3<=head_rst2;
            if(I_camera_frame_start) begin
                // This edge may contain the first word too; retain it in entry zero.
                head_wp<=I_camera_valid?1:0;head_rp<=0;head_count<=I_camera_valid?1:0;
                head_hold<=1;head_reset_seen<=0;
                head_seen<=1;
                if(head_seen && (head_count!=0 || head_hold)) O_capture_fault<=1;
            end else begin
                if(head_rst3) head_reset_seen<=1;
                else if(head_reset_seen) head_hold<=0;
                if(head_push) head_wp<=head_wp+1'b1;
                if(head_pop) head_rp<=head_rp+1'b1;
                case({head_push,head_pop})
                    2'b10:head_count<=head_count+1'b1;
                    2'b01:head_count<=head_count-1'b1;
                    default:head_count<=head_count;
                endcase
                if(head_seen && I_camera_valid && !head_push) O_capture_fault<=1;
            end
        end
    end
    reg         S_camera_frame_start_extend; ///脉冲展宽，同步到ddr_clk时钟域
    reg[3:0]    S_extend_cnt;
    reg         S_camera_frame_start_extend_1d;
    reg         S_camera_frame_start_extend_2d;
    reg         S_camera_frame_start_extend_3d;
    wire        S_frame_start;
    reg[1:0]    S_video_in_wp;       ///写指针
    wire[8:0]   S_fifo_rd_num;      
    wire        S_fifo_rd_en;   
    wire        S_fifo_rd_valid;
    wire[127:0] S_fifo_rd_data; 
    reg         S_ddr_wr_valid;
    reg[9:0]    S_ddr_wr_cnt;

    localparam IMAGE_BASE_ADDR_0 = 25'd0;
    localparam IMAGE_BASE_ADDR_1 = 25'd7000000;
    localparam IMAGE_BASE_ADDR_2 = 25'd14000000;
    localparam IMAGE_BASE_ADDR_3 = 25'd21000000;


    assign S_fifo_rst = S_camera_frame_start_extend_3d;

    // 以完整DDR写突发的占用标志仲裁，避免连续视频写入长期阻塞读通道。
    assign O_video_in_wr_busy = S_ddr_wr_valid;

    w128_d512_fifo U_w128_d512_fifo(
        .rst        ( S_fifo_rst         ),   

        .clkw       ( I_camera_clk       ),     
        .we         ( head_pop           ),
        .di         ( frame_head[head_rp] ),
        .afull      (),
        .full_flag  ( S_fifo_full         ),
        .wrusedw    (),
 
        .clkr       ( I_ddr_clk          ),
        .re         ( S_fifo_rd_en       ), 
        .dout       ( O_ddr_user_wr_data ),  
        .rdusedw    ( S_fifo_rd_num      ),
        .valid      (), 
        .empty_flag (),
        .aempty     ()
    );


    always @(posedge I_camera_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            S_camera_frame_start_extend <= 1'b0;
        else
            if(I_camera_frame_start)
                S_camera_frame_start_extend <= 1'b1;
            else if(S_extend_cnt == 'd7)
                S_camera_frame_start_extend <= 1'b0;
            else
                S_camera_frame_start_extend <= S_camera_frame_start_extend;
    end

	
    always @ (posedge I_camera_clk) begin
    	if(S_camera_frame_start_extend)
        	S_extend_cnt <= S_extend_cnt + 'd1;
      	else
          	S_extend_cnt <= 'd0;
    end


    always @(posedge I_ddr_clk) begin
        S_camera_frame_start_extend_1d <= S_camera_frame_start_extend;
        S_camera_frame_start_extend_2d <= S_camera_frame_start_extend_1d;
        S_camera_frame_start_extend_3d <= S_camera_frame_start_extend_2d;
    end

    assign S_frame_start = ~S_camera_frame_start_extend_3d & S_camera_frame_start_extend_2d;

    // P5 taps: combinational views of the same signals the address/pointer logic uses, so an
    // external observer sees exactly the slot and the cycle the write path acts on.
    assign O_frame_start = S_frame_start;
    assign O_wr_slot     = S_video_in_wp;

	/*
		如果前一帧图像有误少行了，那么地址回退为之前的，覆盖有问题的那帧图像
	*/
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            S_video_in_wp <= 'd0;
        else
            if(I_display_pause)
                S_video_in_wp <= S_video_in_wp;
            else if(S_frame_start)
                begin
                    if(I_mipi_rx_error)
                        S_video_in_wp <= S_video_in_wp;
                    else
                        S_video_in_wp <= S_video_in_wp + 'd1;
                end
            else
                S_video_in_wp <= S_video_in_wp;
    end


    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            O_video_out_rp <= 'd0;
        else
            if(I_display_pause)
                O_video_out_rp <= O_video_out_rp;
            else if(S_frame_start)
                begin
                    case(S_video_in_wp)
                        'd0: O_video_out_rp <= 'd2;
                        'd1: O_video_out_rp <= 'd3;
                        'd2: O_video_out_rp <= 'd0;
                        'd3: O_video_out_rp <= 'd1;
                    endcase
                end
            else
                O_video_out_rp <= O_video_out_rp;
    end

    /*
        fifo的深度是512，实际的深度是510，因此需要注意每次读出的长度避免为256，否则连续两次读写会引起fifo读空，丢失数据
    */
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            S_ddr_wr_valid <= 1'b0;
        else
            if(S_ddr_wr_valid && I_ddr_user_ready && S_ddr_wr_cnt == 'd239)
                S_ddr_wr_valid <= 1'b0;
            else if(S_fifo_rd_num >= 'd240 && (!I_video_out_rd_busy) && (!S_fifo_rst))
                S_ddr_wr_valid <= 1'b1;
            else
                S_ddr_wr_valid <= S_ddr_wr_valid;
    end

    always @(posedge I_ddr_clk) begin
        if(S_ddr_wr_valid)
            begin
                if(I_ddr_user_ready)
                    S_ddr_wr_cnt <= S_ddr_wr_cnt + 'd1;
                else
                    S_ddr_wr_cnt <= S_ddr_wr_cnt;
            end
        else
            S_ddr_wr_cnt <= 'd0;
    end

    assign S_fifo_rd_en = S_ddr_wr_valid & I_ddr_user_ready;

    always @(posedge I_ddr_clk) begin
        O_ddr_user_wr_en <= S_fifo_rd_en;
    end

	/*
		如果前一帧图像有误少行了，那么地址回退为之前的，覆盖有问题的那帧图像
	*/
    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if(!I_rst_n)
            O_ddr_user_addr <= 1'b0;
        else
            if(S_frame_start && (!I_mipi_rx_error))
                begin
                    case(S_video_in_wp)
                        'd0: O_ddr_user_addr <= IMAGE_BASE_ADDR_0;
                        'd1: O_ddr_user_addr <= IMAGE_BASE_ADDR_1;
                        'd2: O_ddr_user_addr <= IMAGE_BASE_ADDR_2;
                        'd3: O_ddr_user_addr <= IMAGE_BASE_ADDR_3;
                    endcase
                end
			else if(S_frame_start && I_mipi_rx_error)
				begin
                	case(S_video_in_wp)
                        'd0: O_ddr_user_addr <= IMAGE_BASE_ADDR_3;
                        'd1: O_ddr_user_addr <= IMAGE_BASE_ADDR_0;
                        'd2: O_ddr_user_addr <= IMAGE_BASE_ADDR_1;
                        'd3: O_ddr_user_addr <= IMAGE_BASE_ADDR_2;
                    endcase
                end
            else if(O_ddr_user_wr_en)
                O_ddr_user_addr <= O_ddr_user_addr + 'd8;
            else    
                O_ddr_user_addr <= O_ddr_user_addr;
    end

    
endmodule
