// Portable model for the fixed DP/NOREG configuration in line_delay_eram.
// It is not a model for other register modes, collisions, resets or ECC.
// Acceptance also runs the installed vendor model with PH1P_PHY_GSR.
`timescale 1ns/1ps

module PH1P_LOGIC_ERAM #(
    parameter DATA_WIDTH_A = 20,
    parameter DATA_WIDTH_B = DATA_WIDTH_A,
    parameter ADDR_WIDTH_A = 10,
    parameter ADDR_WIDTH_B = ADDR_WIDTH_A,
    parameter DATA_DEPTH_A = 2 ** ADDR_WIDTH_A,
    parameter DATA_DEPTH_B = 2 ** ADDR_WIDTH_B,
    parameter BYTE_ENABLE  = 0,
    parameter MODE="DP", REGMODE_A="NOREG", REGMODE_B="NOREG",
    parameter INIT_FILE="NONE", FILL_ALL="NONE", IMPLEMENT="20K",
    parameter BYTE_A       = (BYTE_ENABLE == 0) ? 1 : DATA_WIDTH_A / BYTE_ENABLE,
    parameter BYTE_B       = (BYTE_ENABLE == 0) ? 1 : DATA_WIDTH_B / BYTE_ENABLE
)(
    input  wire [DATA_WIDTH_A-1:0] dia,
    input  wire [ADDR_WIDTH_A-1:0] addra,
    input  wire                    cea,
    input  wire                    ocea,
    input  wire                    clka,
    input  wire                    wea,
    input  wire                    rsta,
    input  wire [BYTE_A-1:0]       bea,
    input  wire [DATA_WIDTH_B-1:0] dib,
    input  wire [ADDR_WIDTH_B-1:0] addrb,
    input  wire                    ceb,
    input  wire                    oceb,
    input  wire                    clkb,
    input  wire                    web,
    input  wire                    rstb,
    input  wire [BYTE_B-1:0]       beb,
    input  wire                    ecc_sbiterrinj,
    input  wire                    ecc_dbiterrinj,
    output wire [DATA_WIDTH_A-1:0] doa,
    output wire [DATA_WIDTH_B-1:0] dob,
    output wire                    ecc_sbiterr,
    output wire                    ecc_dbiterr
);
    reg [DATA_WIDTH_A-1:0] mem [0:DATA_DEPTH_A-1];
    reg [DATA_WIDTH_A-1:0] doa_r;
    reg [DATA_WIDTH_B-1:0] dob_r;
    integer init_word;
    initial begin
        if(FILL_ALL!="NONE" && FILL_ALL!="0")$fatal(1,"Unsupported ERAM stub fill");
        if(FILL_ALL=="0")for(init_word=0;init_word<DATA_DEPTH_A;init_word=init_word+1)mem[init_word]=0;
        if(INIT_FILE!="NONE")$readmemh(INIT_FILE,mem);
    end

    initial if(MODE!="DP" || REGMODE_A!="NOREG" || REGMODE_B!="NOREG" || BYTE_ENABLE!=0 || DATA_WIDTH_A!=DATA_WIDTH_B || ADDR_WIDTH_A!=ADDR_WIDTH_B)
        $fatal(1,"Unsupported ERAM stub configuration");
    always @(posedge clka) begin
        if (cea) begin
            if (wea) mem[addra] <= dia;
            doa_r <= mem[addra];
        end
    end

    always @(posedge clkb) begin
        if (ceb) begin
            if (web) mem[addrb] <= dib;
            dob_r <= mem[addrb];
        end
    end

    assign {doa, dob, ecc_sbiterr, ecc_dbiterr} = {doa_r, dob_r, 1'b0, 1'b0};
endmodule
