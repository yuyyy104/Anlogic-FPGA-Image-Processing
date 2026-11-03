// Integer oracle for the fixed Q8 calibration specification; no DUT state.
function [23:0] corrected;
    input [23:0] v;
    integer r,g,b,o0,o1,o2;
    begin
        r=v[23:16];g=v[15:8];b=v[7:0];
        o0=(286*r-55*g+25*b+128)>>>8;
        o1=(-25*r+283*g-2*b+128)>>>8;
        o2=(9*r-56*g+303*b+128)>>>8;
        o0=o0<0?0:o0>255?255:o0;
        o1=o1<0?0:o1>255?255:o1;
        o2=o2<0?0:o2>255?255:o2;
        corrected={o0[7:0],o1[7:0],o2[7:0]};
    end
endfunction
