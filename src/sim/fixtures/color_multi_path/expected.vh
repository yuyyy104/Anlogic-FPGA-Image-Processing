function [25:0] path_result;input integer dn,slot;begin path_result=0;case(dn*4+slot)
0:path_result=26'h1201a40;
1:path_result=26'h0901860;
2:path_result=26'h2401070;
3:path_result=26'h1b01000;
4:path_result=26'h1201a40;
5:path_result=26'h0901860;
6:path_result=26'h2401070;
7:path_result=26'h1b01000;
endcase end endfunction
function [47:0] path_box;input integer dn,slot;begin path_box=0;case(dn*4+slot)
0:path_box=48'h0a811c02c060;
1:path_box=48'h02807c020074;
2:path_box=48'h0e01480980e0;
3:path_box=48'h154190028064;
4:path_box=48'h0a811c02c060;
5:path_box=48'h02807c020074;
6:path_box=48'h0e01480980e0;
7:path_box=48'h154190028064;
endcase end endfunction
