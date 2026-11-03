`timescale 1ns/1ps
module calibration_osd #(
    parameter X0=608,Y0=328
)(
    input clk,rst_n,frame_start,de,
    input [11:0] x,y,
    input lock_exposure,freeze_wb,enable,sample_valid,
    input [23:0] mean_rgb,
    input [12:0] clip_count,
    input [11:0] shape_w,shape_h,
    input [2:0] reason,
    output wire hit,
    output wire [23:0] color
);
    reg lock_s,wb_s,en_s,valid_s;
    reg [2:0] why_s;
    reg [12:0] values[0:5];
    reg [15:0] digits[0:5];
    reg [28:0] shift_r;
    reg [3:0] steps;
    reg [2:0] field;
    reg [28:0] next_r;
    integer k;
    always @(*) begin
        next_r=shift_r;
        for(k=13;k<29;k=k+4)
            if(next_r[k +:4]>=5) next_r[k +:4]=next_r[k +:4]+3;
        next_r=next_r<<1;
    end
    integer j;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            lock_s<=0;wb_s<=0;en_s<=0;valid_s<=0;why_s<=0;shift_r<=0;steps<=0;field<=0;
            for(j=0;j<6;j=j+1) begin digits[j]<=0;values[j]<=0;end
        end else if(frame_start) begin
            lock_s<=lock_exposure;wb_s<=freeze_wb;en_s<=enable;valid_s<=sample_valid;why_s<=reason;
            values[0]<={5'b0,mean_rgb[23:16]};values[1]<={5'b0,mean_rgb[15:8]};values[2]<={5'b0,mean_rgb[7:0]};
            values[3]<=clip_count;values[4]<={1'b0,shape_w};values[5]<={1'b0,shape_h};
            shift_r<={21'd0,mean_rgb[23:16]};steps<=13;field<=0;
        end else if(steps!=0) begin
            shift_r<=next_r;steps<=steps-1'b1;
            if(steps==1) begin
                digits[field]<=next_r[28:13];
                if(field<5) begin field<=field+1'b1;shift_r<={16'd0,values[field+1'b1]};steps<=13;end
            end
        end
    end
    wire line0=y>=88 && y<104,line1=y>=112 && y<128,line2=y>=136 && y<152;
    wire text_region=de && x>=192 && x<736 && (line0 || (en_s && (line1 || line2)));
    wire [11:0] lx=x-192;
    wire [11:0] ly=line0?y-88:line1?y-112:y-136;
    wire [5:0] cell_idx=lx[9:4];
    reg [7:0] ch;
    function [7:0] digit;
        input [15:0] v;
        input [1:0] pos;
        begin case(pos) 0:digit=48+v[15:12];1:digit=48+v[11:8];2:digit=48+v[7:4];default:digit=48+v[3:0];endcase end
    endfunction
    always @(*) begin
        ch=32;
        if(line0) case(cell_idx)
            0:ch="L";1:ch="O";2:ch="C";3:ch="K";4:ch=":";5:ch=lock_s?"1":"0";
            7:ch="W";8:ch="B";9:ch=":";10:ch=wb_s?"1":"0";
            12:ch="C";13:ch="A";14:ch="L";15:ch=":";16:ch=en_s?"1":"0";
        endcase
        else if(line1) begin
            case(cell_idx)
                0:ch="R";1:ch=":";6:ch="G";7:ch=":";12:ch="B";13:ch=":";
                18:ch="C";19:ch="L";20:ch="I";21:ch="P";22:ch=":";
                29:ch=valid_s?"O":"W";30:ch=valid_s?"K":"A";31:ch=valid_s?32:"I";32:ch=valid_s?32:"T";
            endcase
            if(cell_idx>=2 && cell_idx<=4) ch=valid_s?digit(digits[0],cell_idx-1):"-";
            if(cell_idx>=8 && cell_idx<=10) ch=valid_s?digit(digits[1],cell_idx-7):"-";
            if(cell_idx>=14 && cell_idx<=16) ch=valid_s?digit(digits[2],cell_idx-13):"-";
            if(cell_idx>=23 && cell_idx<=26) ch=valid_s?digit(digits[3],cell_idx-23):"-";
        end else if(line2) begin
            case(cell_idx) 0:ch="W";1:ch=":";7:ch="H";8:ch=":";14:ch="W";15:ch="H";16:ch="Y";17:ch=":";18:ch=48+why_s;endcase
            if(cell_idx>=2 && cell_idx<=5) ch=digit(digits[4],cell_idx-2);
            if(cell_idx>=9 && cell_idx<=12) ch=digit(digits[5],cell_idx-9);
        end
    end
    wire [15:0] glyph;
    osd_char_lib font(.I_char(ch),.I_row(ly[3:0]),.O_row_bits(glyph));
    // The display has three pixels of combined spatial displacement from the raw tap.
    wire box=de && en_s && x>=X0+3 && x<=X0+66 && y>=Y0+3 && y<=Y0+66 &&
             (x==X0+3 || x==X0+66 || y==Y0+3 || y==Y0+66);
    assign hit=text_region || box;
    assign color=box?24'h00ffff:(glyph[15-lx[3:0]]?24'h00ffff:24'h101820);
endmodule
