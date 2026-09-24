function bits = kr_bits_r4s4(v)
%KR_BITS_R4S4  Bits for the original DRHE entropy coder with run-length
%   encoding [2.7.3, 3.5.1]: every non-zero value becomes the 8-bit symbol
%   RRRRSSSS (R4 = number of zeros before it, at most 15; S4 = its region)
%   followed by S4 APPEND bits; the R4S4 symbols are Huffman coded with a
%   dictionary built from the data ("Ideal" in Kiem's Table 2.1; dictionary
%   not counted). ASSUMPTIONS, as in JPEG, which the RRRRSSSS layout follows:
%   runs are taken along the range bins of one ramp, channel and part; a run
%   of 16 zeros is the symbol (15,0); trailing zeros are the symbol (0,0).
%   v: [bins x columns] or [bins x ramps x rx]; each column is one stream.
B = size(v, 1);
V = reshape(v, B, []);
[i, c] = find(V);
s4 = kr_s4(V(sub2ind(size(V), i, c)));
first = [true; c(2:end) ~= c(1:end-1)];
prev = [0; i(1:end-1)]; prev(first) = 0;
run = i - prev - 1;
nZRL = floor(run / 16);
r4 = mod(run, 16);
sym = 16 * r4 + s4;                          % 0..255
% end-of-block for every stream whose last value is zero (or is all zero)
last = zeros(size(V, 2), 1);
if ~isempty(i), last(c) = i; end            % find() is column-sorted
nEOB = nnz(last < B);
cnt = accumarray(sym + 1, 1, [256 1]);
cnt(16*15 + 0 + 1) = cnt(16*15 + 1) + sum(nZRL);   % (15,0)
cnt(1) = cnt(1) + nEOB;                             % (0,0)
len = kr_huffman_lengths(cnt);
bits = sum(cnt .* len) + sum(s4);
end
