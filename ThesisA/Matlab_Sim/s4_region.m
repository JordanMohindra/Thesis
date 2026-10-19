function s4 = s4_region(values)
% S4_REGION Magnitude category used by DRHE and LPC+Huffman.
%   S4 = 0 for 0, otherwise floor(log2(|v|)) + 1, capped at 15.
%   A value costs huffLength(S4) + S4 bits (Huffman code + APPEND bits).
    absVal = abs(double(values));
    s4 = zeros(size(absVal));
    nz = absVal > 0;
    s4(nz) = min(15, floor(log2(absVal(nz))) + 1);
end
