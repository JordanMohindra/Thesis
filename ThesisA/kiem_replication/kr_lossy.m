function [rq, iq, CR] = kr_lossy(re, im, method)
%KR_LOSSY  Approximate versions of the lossy schemes in Kiem's design space
%   [2.7.1, 2.7.2, Table 3.4], applied to the FX16 range-FFT data along the
%   range bins of each ramp and channel. Their exact parameters are
%   proprietary (TI, Infineon) and not given by Kiem; the fixed compression
%   ratios are his. ASSUMPTIONS are marked.
%
%   'CMPRA' 16 complex bins (32 values) in one 256-bit word, CR 2 vs 16 bit
%   'CMPRB' 32 complex bins (64 values) in one 256-bit word, CR 4
%           ASSUMPTION: block floating point, one 4-bit shared exponent per
%           word, the rest split evenly into signed mantissas (7 and 3 bits).
%   'EGE10','EGE8','EGE6','EGE4'  order-k Exponential-Golomb coding of blocks
%           of 8 complex bins, fixed budget of k bits per value (CR 16/k);
%           when a block does not fit, low bits are dropped [2.7.1].
%           ASSUMPTION: an 8-bit block header (4-bit EG order, 4-bit number
%           of dropped bits); the EG order is set from the block's typical
%           bit width, as the TI white paper describes.
[B, M, R] = size(re);
V = zeros(2*B, M*R);                         % re/im interleaved per column
V(1:2:end, :) = reshape(re, B, []);
V(2:2:end, :) = reshape(im, B, []);
switch upper(method)
    case {'CMPRA', 'CMPRB'}
        if strcmpi(method, 'CMPRA'), nv = 32; else, nv = 64; end
        mant = floor((256 - 4) / nv);
        Q = bfp(V, nv, mant);
        CR = nv * 16 / 256;
    otherwise
        k = sscanf(upper(method), 'EGE%d');
        Q = ege(V, 16, k);
        CR = 16 / k;
end
Q = Q + 0;                                    % no negative zeros
rq = reshape(Q(1:2:end, :), B, M, R);
iq = reshape(Q(2:2:end, :), B, M, R);
end

function Q = bfp(V, nv, mant)
[L, C] = size(V);
W = reshape(V, nv, L/nv * C);                % one block per column
lim = 2^(mant-1) - 1;
mx = max(abs(W), [], 1);
s = zeros(1, size(W, 2));
for t = 1:16                                  % smallest shift that fits
    over = round(mx ./ 2.^s) > lim;
    s(over) = s(over) + 1;
end
q = min(max(round(W ./ 2.^s), -lim-1), lim);
Q = reshape(q .* 2.^s, L, C);
end

function Q = ege(V, nv, k)
[L, C] = size(V);
W = reshape(V, nv, L/nv * C);
nb = size(W, 2);
budget = nv * k - 8;
Q = zeros(size(W)); done = false(1, nb);
for d = 0:15
    q = round(W / 2^d);
    u = 2*abs(q) - (q < 0);                   % zig-zag to non-negative
    g = floor(log2(median(u, 1) + 1));        % EG order from typical width
    len = 2*floor(log2(floor(u ./ 2.^g) + 1)) + 1 + g;
    fits = sum(len, 1) <= budget & ~done;
    Q(:, fits) = q(:, fits) * 2^d;
    done = done | fits;
    if all(done), break; end
end
Q(:, ~done) = 0;
Q = reshape(Q, L, C);
end
