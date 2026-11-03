// Single exposure-command source arbiter.
//
// The plan requires an explicit automatic/manual priority where only ONE source
// can drive the sensor exposure/gain write port at any time. P2 keeps the manual
// path live (ae_set.v) and reserves the automatic path for the later image-quality
// stage; i_auto_valid is tied 0 for now, so behaviour is exactly the previous
// manual-only behaviour.
//
// Contract: i_auto_valid must be stable while an exposure transaction is in
// flight (it selects a whole source, not a per-request grant), which is how it is
// driven: from a mode bit, not a per-write decision.
`timescale 1ns / 1ps

module exp_arb (
    input  wire        i_auto_valid,   // 1 = automatic exposure owns the path
    input  wire        i_man_req,
    input  wire [15:0] i_man_ae,
    input  wire [15:0] i_man_ag,
    input  wire        i_auto_req,
    input  wire [15:0] i_auto_ae,
    input  wire [15:0] i_auto_ag,
    output wire        o_req,
    output wire [15:0] o_ae,
    output wire [15:0] o_ag,
    output wire        o_src_auto      // exposed for debug / OSD later
);
    assign o_src_auto = i_auto_valid;
    assign o_req      = i_auto_valid ? i_auto_req : i_man_req;
    assign o_ae       = i_auto_valid ? i_auto_ae  : i_man_ae;
    assign o_ag       = i_auto_valid ? i_auto_ag  : i_man_ag;
endmodule
