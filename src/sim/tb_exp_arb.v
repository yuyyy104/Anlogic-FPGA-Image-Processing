`timescale 1ns/1ps
// TB for exp_arb: the arbiter selects a whole source, never a per-request grant.
//
// Checks (all combinational, so a short settle is enough):
//   1. i_auto_valid = 0 -> o_* must be bit-identical to the manual inputs, for a sweep of
//      manual/auto value combinations (this is the "previous manual-only behaviour" the
//      module promises while the automatic path is idle);
//   2. i_auto_valid = 1 -> o_* must follow the automatic inputs, again for a sweep;
//   3. mutual exclusion: the selected source's request is the only one that can reach o_req
//      (asserted by construction in 1/2, plus an explicit check that changing the *other*
//      source's request/value cannot move the outputs).
module tb_exp_arb;
    reg        auto_valid = 0;
    reg        man_req = 0, auto_req = 0;
    reg [15:0] man_ae = 0, man_ag = 0, auto_ae = 0, auto_ag = 0;
    wire       o_req;
    wire [15:0] o_ae, o_ag;
    wire       o_src_auto;

    exp_arb dut (
        .i_auto_valid(auto_valid),
        .i_man_req(man_req), .i_man_ae(man_ae), .i_man_ag(man_ag),
        .i_auto_req(auto_req), .i_auto_ae(auto_ae), .i_auto_ag(auto_ag),
        .o_req(o_req), .o_ae(o_ae), .o_ag(o_ag), .o_src_auto(o_src_auto)
    );

    integer errors = 0, checks = 0, test_done = 0, i;

    task chk;
        input [127:0] tag;
        input         cond;
        begin
            checks = checks + 1;
            if (!cond) begin
                errors = errors + 1;
                $display("FAIL %0s (req=%b ae=%0d ag=%0d src=%b)", tag, o_req, o_ae, o_ag, o_src_auto);
            end
        end
    endtask

    task settle;
        begin #1; end
    endtask

    initial begin
        // ---- sweep: manual selected -> outputs must equal the manual inputs exactly ----
        auto_valid = 1'b0;
        for (i = 0; i < 8; i = i + 1) begin
            man_req  = i[0];
            man_ae   = 16'h0100 + i;
            man_ag   = 16'h0010 + i;
            auto_req = ~i[0];
            auto_ae  = 16'hf000 + i;
            auto_ag  = 16'h00f0 + i;
            settle;
            chk("man-req",  o_req === man_req);
            chk("man-ae",   o_ae  === man_ae);
            chk("man-ag",   o_ag  === man_ag);
            chk("man-src",  o_src_auto === 1'b0);
        end

        // ---- sweep: automatic selected -> follows the automatic inputs ----
        auto_valid = 1'b1;
        for (i = 0; i < 8; i = i + 1) begin
            man_req  = i[0];
            man_ae   = 16'h0200 + i;
            man_ag   = 16'h0020 + i;
            auto_req = ~i[0];
            auto_ae  = 16'h0abc + i;
            auto_ag  = 16'h0055 + i;
            settle;
            chk("auto-req", o_req === auto_req);
            chk("auto-ae",  o_ae  === auto_ae);
            chk("auto-ag",  o_ag  === auto_ag);
            chk("auto-src", o_src_auto === 1'b1);
        end

        // ---- exclusivity: the unselected source cannot move the outputs ----
        auto_valid = 1'b1;
        auto_req = 1'b1; auto_ae = 16'h0123; auto_ag = 16'h0045;
        settle;
        man_req = 1'b0; man_ae = 16'hdead; man_ag = 16'hbeef;   // change only the loser
        settle;
        chk("auto-immune", (o_req === 1'b1) && (o_ae === 16'h0123) && (o_ag === 16'h0045));

        auto_valid = 1'b0;
        man_req = 1'b1; man_ae = 16'h0321; man_ag = 16'h0067;
        settle;
        auto_req = 1'b0; auto_ae = 16'hffff; auto_ag = 16'hffff; // change only the loser
        settle;
        chk("man-immune", (o_req === 1'b1) && (o_ae === 16'h0321) && (o_ag === 16'h0067));

        test_done = 1;
        if (errors == 0)
            $display("PASS exp_arb checks=%0d errors=0", checks);
        else
            $display("FAIL exp_arb errors=%0d", errors);
        $finish;
    end
endmodule
