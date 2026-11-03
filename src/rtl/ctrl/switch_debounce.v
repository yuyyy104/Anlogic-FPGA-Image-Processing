// Physical SW1 is high in the upper position. Debounce in the pixel domain;
// shared_denoise samples the stable value only at the next frame start.
module switch_debounce #(parameter integer STABLE_CYCLES=1500000)(
    input wire clk,rst_n,raw,
    output reg stable
);
    reg sync1,sync2;
    reg [20:0] count;
    always @(posedge clk or negedge rst_n)
        if(!rst_n) begin sync1<=0;sync2<=0;stable<=0;count<=0;end
        else begin
            sync1<=raw;sync2<=sync1;
            if(sync2==stable) count<=0;
            else if(count==STABLE_CYCLES-1) begin stable<=sync2;count<=0;end
            else count<=count+1'b1;
        end
endmodule
