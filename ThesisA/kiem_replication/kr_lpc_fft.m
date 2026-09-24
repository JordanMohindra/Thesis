function out = kr_lpc_fft(re, im, cfg, lag)
%KR_LPC_FFT  The LPC compressor of this thesis (not the one Kiem cites):
%   second-order linear prediction along SLOW time (across ramps) of the
%   FX16 range-FFT data, coefficients from the Yule-Walker equations per
%   (range bin, RX channel, real/imag part), residual coded with the same
%   Huffman(S4)+APPEND coder as DRHE. Coefficients are quantised to the HLS
%   formats (a1: 16 bits, step 2^-14; a2: 16 bits, step 2^-15) and sent as
%   side information. lag = 1 predicts from the previous ramp (Kiem's radar);
%   lag = nTx is the TDM-corrected variant.
if nargin < 4, lag = 1; end
parts = {re, im};
out.bitsFixed = 0; out.bitsAdaptive = 0; out.lossless = true;
[B, M, R] = size(re);
side = 2 * 16 * B * R * 2;
res = cell(1, 2);
for k = 1:2
    x = parts{k};
    x1 = cat(2, zeros(B, lag, R), x(:, 1:M-lag, :));           % x[m-lag]
    x2 = cat(2, zeros(B, 2*lag, R), x(:, 1:M-2*lag, :));       % x[m-2lag]
    R0 = sum(x.^2, 2); R1 = sum(x .* x1, 2); R2 = sum(x .* x2, 2);
    den = R0.^2 - R1.^2;
    a1 = R1 .* (R0 - R2) ./ den;
    a2 = (R0 .* R2 - R1.^2) ./ den;
    bad = ~(den ~= 0) | ~isfinite(a1) | ~isfinite(a2) | abs(a2) >= 1 | abs(a1) >= 1 - a2;
    a1(bad) = 0; a2(bad) = 0;
    a1 = min(max(round(a1 * 2^14), -2^15), 2^15-1) / 2^14;
    a2 = min(max(round(a2 * 2^15), -2^15), 2^15-1) / 2^15;
    e = kr_wrap16(x - round(a1 .* x1 + a2 .* x2));
    res{k} = e;
    out.bitsFixed    = out.bitsFixed    + kr_bits_s4(e, cfg.huffLenFixed);
    out.bitsAdaptive = out.bitsAdaptive + kr_bits_s4(e, []);
    % decode sample by sample, as a receiver would, and check
    y = zeros(B, M, R);
    for m = 1:M
        p1 = zeros(B, 1, R); p2 = zeros(B, 1, R);
        if m > lag,   p1 = y(:, m-lag, :);   end
        if m > 2*lag, p2 = y(:, m-2*lag, :); end
        y(:, m, :) = kr_wrap16(e(:, m, :) + round(a1 .* p1 + a2 .* p2));
    end
    out.lossless = out.lossless && isequal(y, x);
end
out.sideBits = side;
out.bitsFixed = out.bitsFixed + side;
out.bitsAdaptive = out.bitsAdaptive + side;
out.resRe = res{1}; out.resIm = res{2};
end
