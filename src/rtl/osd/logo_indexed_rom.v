// Lossless index and palette reads take two clocks from the raw raster tap.
module logo_indexed_rom(input clk,input [14:0] addr,output wire [24:0] pixel);
 wire [13:0] map_addr=addr>=15'd5494 && addr<=15'd20426 ? addr-15'd5494 : 14'd16383;
 wire [9:0] index;
 PH1P_LOGIC_ERAM #(.DATA_WIDTH_A(10),.DATA_WIDTH_B(10),.ADDR_WIDTH_A(14),.ADDR_WIDTH_B(14),
  .DATA_DEPTH_A(16384),.DATA_DEPTH_B(16384),.BYTE_ENABLE(0),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
  .INIT_FILE("D:/fpga_2/fpga-competition-2026-main/src/rtl/osd/logo_data/index.dath")) map_rom(
  .clka(clk),.cea(1'b0),.ocea(1'b0),.wea(1'b0),.addra(14'd0),.dia(10'd0),.rsta(1'b0),.bea(1'b1),.doa(),
  .clkb(clk),.ceb(1'b1),.oceb(1'b0),.web(1'b0),.addrb(map_addr),.dib(10'd0),.rstb(1'b0),.beb(1'b1),.dob(index),
  .ecc_sbiterrinj(1'b0),.ecc_dbiterrinj(1'b0),.ecc_sbiterr(),.ecc_dbiterr());
 PH1P_LOGIC_ERAM #(.DATA_WIDTH_A(25),.DATA_WIDTH_B(25),.ADDR_WIDTH_A(10),.ADDR_WIDTH_B(10),
  .DATA_DEPTH_A(1024),.DATA_DEPTH_B(1024),.BYTE_ENABLE(0),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
  .INIT_FILE("D:/fpga_2/fpga-competition-2026-main/src/rtl/osd/logo_data/palette.dath")) palette_rom(
  .clka(clk),.cea(1'b0),.ocea(1'b0),.wea(1'b0),.addra(10'd0),.dia(25'd0),.rsta(1'b0),.bea(1'b1),.doa(),
  .clkb(clk),.ceb(1'b1),.oceb(1'b0),.web(1'b0),.addrb(index),.dib(25'd0),.rstb(1'b0),.beb(1'b1),.dob(pixel),
  .ecc_sbiterrinj(1'b0),.ecc_dbiterrinj(1'b0),.ecc_sbiterr(),.ecc_dbiterr());
endmodule
