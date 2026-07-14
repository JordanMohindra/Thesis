function out = quantize_half(x)
% QUANTIZE_HALF Snap values to IEEE 754 half precision (FP16 grid).
%   Uses the MATLAB half() type when available, otherwise emulates the
%   1+5+10 bit format (10 stored mantissa bits). Shared by compress_fp16
%   and the DRHE-FP16 path so both use the same quantisation grid.
%
%   See also: COMPRESS_FP16, COMPRESS_DRHE_FP16.

    try
        out = double(half(x));
    catch
        halfMax = 65504;
        x = max(min(x, halfMax), -halfMax);
        sgn = sign(x);
        absX = abs(x);
        exponent = floor(log2(absX + (absX == 0)));
        quantum = 2.^(exponent - 10);
        out = sgn .* round(absX ./ quantum) .* quantum;
        out(x == 0) = 0;
    end
end
