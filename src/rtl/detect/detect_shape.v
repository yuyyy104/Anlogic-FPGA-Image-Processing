`timescale 1ns/1ps
// P3 detect: streaming single-target statistics over the raw display-side pixel
// stream (the source raster). Interface contract: docs/接口-算法挂载点.md,
// section "P3 检测支路接口冻结".
//
// Denoise rule - causal and exactly modelled by src/sim/tb_detect.v:
//   a pixel at column x counts only when it is the centre of three consecutive
//   target pixels, i.e. target(x-1) & target(x) & target(x+1), with 1 <= x <= W-3.
//   A run of length L therefore keeps L-2 counted pixels, trimmed symmetrically by
//   one pixel at each end, and a run shorter than three pixels vanishes. The window
//   never crosses a row boundary: x = 0 is excluded (its left neighbour belongs to
//   the previous row) and x >= W-2 is excluded by the row-end condition.
//
// Frame flow: statistics accumulate while de is high; the frame is finalised at
// the last row's `last` (w*h needs one small serial multiply, done in the vertical
// blanking) and the result is latched atomically at the next `user`. The serial
// product and registered classification complete before publication; cleanup
// requires at least sixteen blank clocks between the source tail and next user.
//
// Classes: 0 = no target, 1 = circle, 2 = rectangle, 3 = unknown. Classification
// tolerates fragmented colour masks through actual occupancy and edge profiles.
// It is a single candidate heuristic; nearby targets and thick rings can merge.
// Optional tracking bounds sparse, area-preserving UNKNOWN box expansions.
// Bbox and area are
// in source-raster coordinates; the display position of a source pixel is +2 in
// both axes (display (r,c) shows source (r-2,c-2)).
module detect_shape #(
    parameter integer H_ACTIVE = 1280,
    parameter integer V_ACTIVE = 720,
    parameter [7:0]   THR_RG   = 8'd24,   // R must lead G by at least this
    parameter [7:0]   THR_RB   = 8'd24,   // R must lead B by at least this
    parameter integer AREA_MIN = 64,      // counted pixels; below this: no target
    parameter integer TRACK_BOX = 0,
    parameter integer BOX_HOLD = 6,
    parameter integer MASK_CLEANUP = 1,
    parameter integer GEOMETRY = 0
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [23:0] rgb_in,
    input  wire        de,
    input  wire        user,        // frame start: first active pixel of the frame
    input  wire        last,        // last active pixel of the row
    output reg         res_valid,
    output reg  [1:0]  res_cls,
    output reg  [19:0] res_area,
    output reg  [11:0] res_xmin,
    output reg  [11:0] res_xmax,
    output reg  [11:0] res_ymin,
    output reg  [11:0] res_ymax,
    output reg  [23:0] res_frame_id,
    output reg [2:0] res_reason
);
    localparam [11:0] X_ALL1 = 12'hfff;
    localparam [11:0] Y_ALL1 = 12'hfff;

    // ---------------- target colour test ----------------
    wire [7:0] px_r = rgb_in[23:16];
    wire [7:0] px_g = rgb_in[15:8];
    wire [7:0] px_b = rgb_in[7:0];
    wire [8:0] g_lim = {1'b0, px_g} + {1'b0, THR_RG};
    wire [8:0] b_lim = {1'b0, px_b} + {1'b0, THR_RB};
    // Relative red dominance rejects warm grey/skin whose absolute R-G gap
    // alone could cover most of the frame. Equality at R=1.5*G/B is accepted.
    wire [9:0] twice_r={1'b0,px_r,1'b0};
    wire [9:0] three_g={1'b0,px_g,1'b0}+{2'b00,px_g};
    wire [9:0] three_b={1'b0,px_b,1'b0}+{2'b00,px_b};
    wire red_pix = ({1'b0, px_r} >= g_lim) && ({1'b0, px_r} >= b_lim) &&
                   twice_r>=three_g && twice_r>=three_b;

    // ---------------- row / column counters (active pixels only) ----------------
    // Same shape as preproc_pipe: the value used this cycle is forced to 0 on the
    // frame-start pixel, and the counter is updated at the end of the cycle.
    reg  [11:0] col, row;
    wire [11:0] xi = user ? 12'd0 : col;
    wire [11:0] yi = user ? 12'd0 : row;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin col <= 12'd0; row <= 12'd0; end
        else if (de) begin
            col <= last ? 12'd0 : xi + 12'd1;
            row <= last ? yi + 12'd1 : yi;
        end
    end

    // Fill a non-red centre only when three of its four axial neighbours are
    // red. Isolated threshold failures, including boundary speckles, are repaired;
    // straight one-pixel cracks have only two red neighbours and remain visible.
    // The two RAMs read the incoming column and write the preceding registered
    // column, exactly as the shared quality stage. Display timing is untouched.
    wire mask_red,mask_de,mask_last;
    wire [11:0] mask_x,mask_y;
    generate if(MASK_CLEANUP!=0) begin : g_mask
        localparam integer AW=(H_ACTIVE<=2)?1:$clog2(H_ACTIVE);
        reg [11:0] x1,y1;
        reg red1,de1,last1;
        wire [1:0] ld;
        genvar line;
        for(line=0;line<2;line=line+1) begin : lines
            PH1P_LOGIC_ERAM #(.DATA_WIDTH_A(1),.DATA_WIDTH_B(1),
                .ADDR_WIDTH_A(AW),.ADDR_WIDTH_B(AW),
                .DATA_DEPTH_A(H_ACTIVE),.DATA_DEPTH_B(H_ACTIVE),.BYTE_ENABLE(0),
                .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG")) ram (
                .clka(clk),.cea(1'b1),.ocea(1'b0),.wea(rst_n && de1),
                .addra(x1[AW-1:0]),.dia(line==0 ? red1 : ld[0]),
                .rsta(1'b0),.bea(1'b1),.doa(),
                .clkb(clk),.ceb(de),.oceb(1'b1),.web(1'b0),
                .addrb(xi[AW-1:0]),.dib(1'b0),.rstb(1'b0),.beb(1'b1),.dob(ld[line]),
                .ecc_sbiterrinj(1'b0),.ecc_dbiterrinj(1'b0),.ecc_sbiterr(),.ecc_dbiterr());
        end
        wire [2:0] p={red1,(y1>=1 ? ld[0] : 1'b0),(y1>=2 ? ld[1] : 1'b0)};
        reg [1:0] h[0:2];
        wire north=h[0][0],south=h[2][0];
        wire west=x1>=2 ? h[1][1] : 1'b0,east=p[1];
        wire fill=(north && south && (west || east)) ||
                  (west && east && (north || south));
        reg mr,md,ml;
        reg [11:0] mx,my;
        integer a;
        assign mask_red=mr;assign mask_de=md;assign mask_last=ml;
        assign mask_x=mx;assign mask_y=my;
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin
                x1<=0;y1<=0;red1<=0;de1<=0;last1<=0;
                mr<=0;md<=0;ml<=0;mx<=0;my<=0;
                for(a=0;a<3;a=a+1) h[a]<=0;
            end else begin
                x1<=xi;y1<=yi;red1<=red_pix;de1<=de;last1<=last;
                md<=de1 && x1>=1 && y1>=1;
                ml<=de1 && last1 && y1>=1;
                mx<=x1-1'b1;my<=y1-1'b1;
                mr<=de1 && x1>=1 && y1>=1 && (h[1][0] || fill);
                if(de1) for(a=0;a<3;a=a+1)
                    h[a]<={x1==0 ? 1'b0 : h[a][0],p[a]};
            end
        end
    end else begin : g_no_mask
        assign mask_red=red_pix;assign mask_de=de;assign mask_last=last;
        assign mask_x=xi;assign mask_y=yi;
    end endgenerate

    // ---------------- two-cycle delay line + three-tap run window ----------------
    // The counted pixel is the one two cycles back: its own row-end flag and the
    // next pixel's row-end flag must both be clear, which keeps the three-pixel
    // window inside one row.
    reg [11:0] x_d1, x_d2, y_d1, y_d2;
    reg        de_d1, de_d2, last_d1, last_d2;
    reg [2:0]  red_sr;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            {x_d1,x_d2,y_d1,y_d2} <= {12'd0,12'd0,12'd0,12'd0};
            {de_d1,de_d2,last_d1,last_d2} <= {1'b0,1'b0,1'b0,1'b0};
            red_sr <= 3'd0;
        end else begin
            {x_d1,x_d2} <= {mask_x,x_d1};
            {y_d1,y_d2} <= {mask_y,y_d1};
            {de_d1,de_d2} <= {mask_de,de_d1};
            {last_d1,last_d2} <= {mask_last,last_d1};
            red_sr <= {red_sr[1:0], mask_red};
        end
    end
    // The counted pixel is the one two cycles back: its own row-end flag and the
    // next pixel's row-end flag must both be clear, and column 0 is excluded, so the
    // three-pixel window is always inside one row. Rows V_ACTIVE-2 and V_ACTIVE-1 are
    // excluded because the display shows source (r-2,c-2): those two rows can never
    // be displayed, and counting them would inflate the area and push the box's
    // bottom edge out of the raster (found by the P3 independent review).
    wire eligible = de_d2 && de_d1 &&
               y_d1==y_d2 && x_d1==x_d2+1'b1 && x_d2>=1 && x_d2<=H_ACTIVE-3 &&
               (y_d2 < (V_ACTIVE[11:0] - 12'd2));
    wire acc=eligible && red_sr[0] && red_sr[1] && red_sr[2];
    // ---------------- frame-end detection (delayed to drain the delay line) ----------------
    wire frame_end = last && (yi == (V_ACTIVE[11:0] - 12'd1));
    reg frame_end_d1,frame_end_d2,frame_end_d3,frame_end_d4;
    wire finalize_frame=MASK_CLEANUP!=0 ? frame_end_d4 : frame_end_d2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin frame_end_d1<=0;frame_end_d2<=0;frame_end_d3<=0;frame_end_d4<=0;end
        else begin frame_end_d1<=frame_end;frame_end_d2<=frame_end_d1;
            frame_end_d3<=frame_end_d2;frame_end_d4<=frame_end_d3;end
    end

    // Occupancy and row spans use only real accepted pixels. Do not restore
    // virtual hole area: dense threshold speckles must not exhaust a topology
    // table, and sparse stripes must not be filled into a rectangle.
    reg [19:0] area;
    reg [11:0] xmin,xmax,ymin,ymax,rows_tgt,row_first,row_last;
    reg row_has_tgt;
    reg [2:0] first_rows;
    reg [13:0] first_spans,last_spans,first_points,last_points;
    reg [11:0] row_points,points0,points1,points2,points3;
    reg [11:0] recent0,recent1,recent2,recent3;
    wire [11:0] row_span=row_last-row_first+12'd1;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            {area,xmin,xmax,ymin,ymax}<={20'd0,X_ALL1,12'd0,Y_ALL1,12'd0};
            {rows_tgt,row_has_tgt,row_first,row_last,first_rows,first_spans,last_spans,recent0,recent1,recent2,recent3}<=0;
            {row_points,first_points,last_points,points0,points1,points2,points3}<=0;
        end else if(finalize_frame)begin
            {area,xmin,xmax,ymin,ymax}<={20'd0,X_ALL1,12'd0,Y_ALL1,12'd0};
            {rows_tgt,row_has_tgt,row_first,row_last,first_rows,first_spans,last_spans,recent0,recent1,recent2,recent3}<=0;
            {row_points,first_points,last_points,points0,points1,points2,points3}<=0;
        end else if(acc)begin
            area<=area+20'd1;
            if(x_d2<xmin)xmin<=x_d2;
            if(x_d2>xmax)xmax<=x_d2;
            if(y_d2<ymin)ymin<=y_d2;
            if(y_d2>ymax)ymax<=y_d2;
            if(!row_has_tgt)row_first<=x_d2;
            row_points<=row_has_tgt ? row_points+12'd1 : 12'd1;
            row_last<=x_d2;row_has_tgt<=1;
        end else if(last_d2)begin
            if(row_has_tgt)begin
                rows_tgt<=rows_tgt+12'd1;
                if(first_rows<4)begin
                    first_rows<=first_rows+1'b1;first_spans<=first_spans+{2'd0,row_span};
                    first_points<=first_points+{2'd0,row_points};
                end
                last_spans<=last_spans-{2'd0,recent3}+{2'd0,row_span};
                last_points<=last_points-{2'd0,points3}+{2'd0,row_points};
                {recent3,recent2,recent1,recent0}<={recent2,recent1,recent0,row_span};
                {points3,points2,points1,points0}<={points2,points1,points0,row_points};
            end
            row_has_tgt<=0;
        end
    end

    // ---------------- finalise: one serial multiply in the vertical blanking ----------------
    localparam [1:0] F_IDLE = 2'd0, F_MUL = 2'd1, F_RDY = 2'd2;
    reg [1:0]  fst;
    // The serial multiplier shifts the multiplicand left on every step, so it must
    // hold bbox_width << 10: 1280 << 10 = 1310720, i.e. 21 bits. Keeping m_a at the
    // bbox width (11 bits) silently dropped the high bits for widths >= 256 and made
    // w*h wrong (found by tb_detect_big.v at radius 200: a large circle was then
    // classified as a rectangle).
    reg [20:0] m_a;          // multiplicand (bbox width shifted left)
    reg [9:0]  m_b;          // multiplier  (bbox height, <= V_ACTIVE)
    reg [20:0] m_p;
    reg [3:0]  m_cnt;
    reg [19:0] f_area;
    reg [11:0] f_xmin, f_xmax, f_ymin, f_ymax, fw, fh;
    reg [11:0] f_rows;
    reg [13:0] f_first_spans,f_last_spans,f_first_points,f_last_points;
    reg [23:0] f_fid, fid;

    wire [11:0] w_now = (area == 20'd0) ? 12'd0 : (xmax - xmin + 12'd1);
    wire [11:0] h_now = (area == 20'd0) ? 12'd0 : (ymax - ymin + 12'd1);
    wire geom_ready,geom_rect;
    generate if(GEOMETRY!=0) begin : g_edges
        shape_edges #(.H_ACTIVE(H_ACTIVE),.V_ACTIVE(V_ACTIVE)) edges(
            .clk(clk),.rst_n(rst_n),.user(user),.row_write(last_d2 && de_d2),.row_valid(row_has_tgt),
            .finish(finalize_frame),.row_y(y_d2),.row_left(row_first),.row_right(row_last),.row_points(row_points),
            .bbox_w(w_now),.bbox_h(h_now),.area(area),.ready(geom_ready),.rectangle(geom_rect));
    end else begin assign geom_ready=1;assign geom_rect=0;end endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            {fst,m_a,m_b,m_p,m_cnt} <= {F_IDLE,11'd0,10'd0,21'd0,4'd0};
            {f_area,f_xmin,f_xmax,f_ymin,f_ymax} <= {20'd0,X_ALL1,12'd0,Y_ALL1,12'd0};
            {fw,fh,f_rows,f_first_spans,f_last_spans,f_first_points,f_last_points} <= 0;
            f_fid <= 24'hffffff; fid <= 24'd0;   // no frame published yet
        end else begin
            case (fst)
                F_IDLE: if (finalize_frame) begin
                    {f_area,f_xmin,f_xmax,f_ymin,f_ymax} <= {area,xmin,xmax,ymin,ymax};
                    {fw,fh,f_first_spans,f_last_spans} <= {w_now,h_now,first_spans,last_spans};
                    {f_first_points,f_last_points}<={first_points,last_points};
                    f_rows <= (row_has_tgt) ? rows_tgt + 12'd1 : rows_tgt;
                    {f_fid,fid} <= {fid,fid + 24'd1};
                    {m_a,m_b,m_p,m_cnt} <= {{10'd0, w_now[10:0]},h_now[9:0],21'd0,4'd0};
                    fst <= F_MUL;
                end
                F_MUL: begin
                    if (m_cnt == 4'd10) fst <= F_RDY;
                    else begin
                        if (m_b[0]) m_p <= m_p + m_a;
                        m_a <= m_a << 1;
                        m_b <= m_b >> 1;
                        m_cnt <= m_cnt + 4'd1;
                    end
                end
                F_RDY: if (user) fst <= F_IDLE;   // hold the finished product until published
                default: fst <= F_IDLE;
            endcase
        end
    end

    // Dense rectangles: actual fill >= 13/16. Larger rectangles with a
    // damaged centre may use fill >= 9/16 when both end profiles stay broad
    // and have at least half their span occupied by real accepted pixels.
    // Circle fill is 9/16 .. 13/16, with up to 2:1 perspective aspect.
    // A quarter of the bounding height may lack accepted pixels.
    wire [22:0] prod={2'b0,m_p};
    wire [23:0] a16={f_area,4'b0};
    wire [23:0] p13=({1'b0,prod}<<3)+({1'b0,prod}<<2)+{1'b0,prod};
    wire [23:0] p9=({1'b0,prod}<<3)+{1'b0,prod};
    wire [11:0] dxy=fw>=fh ? fw-fh : fh-fw;
    wire [11:0] dmx=fw>=fh ? fw : fh;
    wire c_aspect={2'b0,dxy,1'b0}<={3'b0,dmx}+15'd2;
    wire [14:0] width5=({3'd0,fw}<<2)+{3'd0,fw};
    wire c_outline=fw>=32 && fh>=32 && {f_first_spans,1'b0}>=width5 && {f_last_spans,1'b0}>=width5 &&
        {f_first_points,1'b0}>={1'b0,f_first_spans} && {f_last_points,1'b0}>={1'b0,f_last_spans};
    wire c_rows={1'b0,f_rows,2'b0}>=(({3'd0,fh}<<1)+{3'd0,fh});
    wire c_rect=geom_rect || a16>=p13 || (c_outline && a16>=p9);
    wire c_circ=a16>=p9 && a16<p13 && c_aspect;
    wire c_valid=f_area>=AREA_MIN[19:0];
    wire [1:0] c_cls=!c_valid ? 0 : !geom_ready || !c_rows ? 3 : c_rect ? 2 : c_circ ? 1 : 3;

    // A few false-red pixels on a caption can enlarge the box while leaving
    // its area unchanged, even when relaxed geometry produces a known class.
    // Hold at most BOX_HOLD publications;
    // persistent new geometry is then published, and NONE clears at once.
    wire [12:0] old_w={1'b0,res_xmax}-{1'b0,res_xmin}+13'd1;
    wire [12:0] old_h={1'b0,res_ymax}-{1'b0,res_ymin}+13'd1;
    wire [23:0] old_a={4'b0,res_area},new_a8={1'b0,f_area,3'b0};
    wire same_area=new_a8>=((old_a<<3)-old_a) && new_a8<=((old_a<<3)+old_a);
    wire expanded=({2'b0,fw,1'b0}>(({2'b0,old_w}<<1)+{2'b0,old_w})) ||
                  ({2'b0,fh,1'b0}>(({2'b0,old_h}<<1)+{2'b0,old_h}));
    wire suspect=TRACK_BOX!=0 && geom_ready && res_valid && c_valid && same_area && expanded;
    reg [$clog2(BOX_HOLD+1)-1:0] rejected_boxes;
    reg publish_valid,publish_suspect;
    reg [1:0] publish_class;
    reg [2:0] publish_reason;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin publish_valid<=0;publish_suspect<=0;publish_class<=0;publish_reason<=0;end
        else if(fst==F_RDY)begin
            publish_valid<=c_valid;publish_class<=c_cls;publish_suspect<=suspect;
            publish_reason<=!c_valid ? 0 : !geom_ready ? 5 : (c_rows && (c_rect || c_circ)) ? 0 :
                !c_rows ? 2 : (a16>=p9 && a16<p13 && !c_aspect) ? 4 : 3;
        end
    end

    // ---------------- publish at the frame boundary ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            {res_valid,res_cls,res_area} <= {1'b0,2'd0,20'd0};
            {res_xmin,res_xmax,res_ymin,res_ymax} <= {12'd0,12'd0,12'd0,12'd0};
            res_frame_id <= 24'hffffff;
            res_reason<=0;
            rejected_boxes<=0;
        end else if (user) begin
          if(publish_suspect && rejected_boxes<BOX_HOLD) begin
            rejected_boxes<=rejected_boxes+1'b1;
            res_reason<=7;
          end else begin
            rejected_boxes<=0;
            res_valid <= publish_valid;
            res_cls   <= publish_class;
            res_area  <= f_area;
            // A frame with fewer counted pixels than AREA_MIN is "no target": the
            // published bbox must be cleared, not left holding the small blob (P3
            // independent review, F3).
            res_xmin  <= (!publish_valid) ? 12'd0 : f_xmin;
            res_xmax  <= (!publish_valid) ? 12'd0 : f_xmax;
            res_ymin  <= (!publish_valid) ? 12'd0 : f_ymin;
            res_ymax  <= (!publish_valid) ? 12'd0 : f_ymax;
            res_frame_id <= f_fid;
            res_reason<=publish_reason;
          end
        end
    end
endmodule
