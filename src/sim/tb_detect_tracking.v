`timescale 1ns/1ps
module tb_detect_tracking;
    localparam W=96,H=64,HOLD=6;
    reg clk=0,rst=0,de=0,user=0,last=0;always #5 clk=~clk;
    reg [23:0] rgb=0;wire valid;wire [1:0] cls;wire [2:0] why;
    wire [19:0] area;wire [11:0] x0,x1,y0,y1;wire [23:0] fid;
    detect_shape #(.H_ACTIVE(W),.V_ACTIVE(H),.MASK_CLEANUP(0),.TRACK_BOX(1),.BOX_HOLD(HOLD)) dut(.clk(clk),.rst_n(rst),.rgb_in(rgb),.de(de),.user(user),.last(last),
        .res_valid(valid),.res_cls(cls),.res_reason(why),.res_area(area),.res_xmin(x0),.res_xmax(x1),.res_ymin(y0),.res_ymax(y1),.res_frame_id(fid));
    integer errors=0,checks=0,xx,yy,n,base_len,extra,len,left;reg test_done=0;
    reg [97:0] previous;wire [97:0] packet={valid,cls,area,x0,x1,y0,y1,fid,why};
    always @(posedge clk)begin #1;if(rst && !test_done)begin checks=checks+1;if(packet!==previous && !user)begin errors=errors+1;$display("FAIL tracking packet tore");end end previous=packet;end
    task check;input [255:0] name;input ok;
        begin checks=checks+1;if(!ok)begin errors=errors+1;$display("FAIL %s cls=%0d area=%0d width=%0d why=%0d fid=%0d",name,cls,area,x1-x0+1,why,fid);end end
    endtask
    task reset_dut;
        begin @(negedge clk);rst=0;de=0;user=0;last=0;repeat(4)@(negedge clk);rst=1;end
    endtask
    task frame;
        input integer ww,hh,aa;
        begin
            base_len=hh>2?(aa-2*ww)/(hh-2):0;extra=hh>2?(aa-2*ww)%(hh-2):0;
            for(yy=0;yy<H;yy=yy+1)begin
                len=yy==12 || yy==11+hh ? ww : base_len+(yy-12<=extra);left=10+(ww-len)/2;
                for(xx=0;xx<W;xx=xx+1)begin
                    @(negedge clk);de=1;user=(xx==0&&yy==0);last=(xx==W-1);
                    rgb=ww>0&&yy>=12&&yy<12+hh&&xx>=left-1&&xx<left+len+1?24'hff2020:24'h303030;
                end
                @(negedge clk);de=0;user=0;last=0;repeat(4)@(negedge clk);
            end
            repeat(32)@(negedge clk);
        end
    endtask
    integer saved_id,saved_class;
    task holds;
        input integer hh,aa;
        begin
            reset_dut();frame(30,hh,aa);frame(30,hh,aa);saved_class=cls;
            check("baseline target",valid && x1-x0+1==30 && area==aa);
            // This user publishes the last normal frame; the enlarged result
            // cannot publish until the next user. Save that effective packet ID.
            frame(46,hh,aa);saved_id=fid;
            for(n=0;n<HOLD;n=n+1)begin frame(46,hh,aa);check("abnormal enlargement bounded hold",valid && x1-x0+1==30 && cls==saved_class && area==aa && fid==saved_id && why==7);end
            frame(46,hh,aa);check("persistent new unknown adopted",valid && x1-x0+1==46 && cls==3 && why!=7 && fid>saved_id);
            frame(30,hh,aa);frame(30,hh,aa);check("normal target restores promptly",x1-x0+1==30 && cls==saved_class && why==0 || (x1-x0+1==30 && cls==3 && why==3));
        end
    endtask
    task boundary;
        input integer aa,want_hold;
        begin
            reset_dut();frame(30,20,320);frame(30,20,320);frame(46,20,aa);frame(46,20,aa);
            check("area ratio equality or adjacent boundary",want_hold?(why==7 && area==320 && x1-x0+1==30):(why!=7 && area==aa && x1-x0+1==46));
        end
    endtask
    initial begin
        holds(20,300);holds(20,600);holds(30,700);
        boundary(280,1);boundary(279,0);boundary(360,1);boundary(361,0);
        reset_dut();frame(30,20,300);frame(30,20,300);frame(45,20,300);frame(45,20,300);
        check("exact one point five size is not outlier",x1-x0+1==45 && why!=7);
        reset_dut();frame(30,20,300);frame(30,20,300);frame(46,20,300);frame(46,20,300);
        check("hold before clear",why==7);
        frame(0,0,0);frame(0,0,0);check("NONE clears immediately",!valid && cls==0 && area==0 && x0==0 && x1==0 && y0==0 && y1==0 && why==0);
        reset_dut();check("epoch reset clears box and hold",!valid && dut.rejected_boxes==0);
        // A low-density expansion can now receive a known class. It still
        // has to satisfy the same bounded publication protection.
        reset_dut();frame(30,30,900);frame(30,30,900);
        check("known rectangle baseline",valid && cls==2 && area==900);
        frame(46,30,900);saved_id=fid;
        for(n=0;n<HOLD;n=n+1)begin
            frame(46,30,900);check("known class cannot bypass expansion hold",cls==2 && x1-x0+1==30 && area==900 && fid==saved_id && why==7);
        end
        frame(46,30,900);check("persistent known geometry adopted",cls==1 && x1-x0+1==46 && area==900 && why==0 && fid>saved_id);
        reset_dut();frame(30,30,900);frame(30,30,900);frame(45,30,900);frame(45,30,900);
        check("known geometry at exact 1.5 changes promptly",cls==1 && x1-x0+1==45 && why==0);
        test_done=1;if(errors==0)$display("PASS detect_tracking checks=%0d HOLD6 area_boundaries epoch_none atomic_packet errors=0",checks);else $display("FAIL detect_tracking errors=%0d",errors);$finish;
    end
endmodule
