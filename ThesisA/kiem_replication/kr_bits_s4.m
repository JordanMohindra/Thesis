function [bits, s4] = kr_bits_s4(v, huffLen)
%KR_BITS_S4  Bits to code integer values with Kiem's final scheme [3.5.1-3.5.3]:
%   each value -> Huffman(S4) + APPEND, where APPEND has S4 bits.
%   huffLen: code length of each S4 symbol 0..15. If empty, an optimal
%   Huffman code is built from the data ("DRHE without RLE" with an ideal
%   dictionary); the 16 code lengths (4 bits each) are then added as side
%   information.
s4 = kr_s4(v(:));
cnt = accumarray(s4 + 1, 1, [16 1]);
if nargin < 2 || isempty(huffLen)
    huffLen = kr_huffman_lengths(cnt).';
    side = 16 * 4;
else
    side = 0;
end
bits = sum(cnt .* huffLen(:)) + sum(s4) + side;
end
