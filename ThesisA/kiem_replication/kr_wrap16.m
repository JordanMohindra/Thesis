function y = kr_wrap16(x)
%KR_WRAP16  Two's-complement int16 wrap-around (the difference is stored in
%   16 bits, [3.5.3] "The resulting difference is in the 16-bit integer format").
y = mod(x + 32768, 65536) - 32768;
end
