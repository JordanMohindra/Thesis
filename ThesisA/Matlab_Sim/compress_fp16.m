function compressedData = compress_fp16(inputData)
% COMPRESS_FP16 Converts range FFT data to 16-bit floating-point (half precision).
%   As described in Section 3.4 of Kiem's thesis, FP16 is the reference format.
%   IEEE 754 half-precision: 1 sign bit, 5 exponent bits, 10 mantissa bits.
%
%   The data is first normalized by its maximum value to fit within half-precision
%   representable range, then stored in half. The floating-point exponent gives
%   each value adaptive precision proportional to its magnitude - this preserves
%   both large (target peaks) and small (noise) values better than fixed-point.
%
%   CR = 1 (baseline reference format).
%
%   Input:
%     inputData - complex double [numRangeBins x numRamps x numRxChannels]
%
%   Output:
%     compressedData - struct with half-precision data and scale factor

    realPart = real(inputData);
    imagPart = imag(inputData);

    % Scale to fit within half-precision range (max representable = 65504)
    maxVal = max(abs([realPart(:); imagPart(:)]));
    halfMax = 65504;

    if maxVal > 0
        scaleFactor = halfMax / maxVal;
    else
        scaleFactor = 1;
    end

    realScaled = realPart * scaleFactor;
    imagScaled = imagPart * scaleFactor;

    % Convert to half-precision (or emulate if toolbox unavailable)
    try
        compressedData.real_part = half(realScaled);
        compressedData.imag_part = half(imagScaled);
    catch
        compressedData.real_part = emulateHalf(realScaled);
        compressedData.imag_part = emulateHalf(imagScaled);
    end

    compressedData.scaleFactor = scaleFactor;
    compressedData.format = 'fp16';
end

function out = emulateHalf(x)
% EMULATEHALF Vectorized IEEE 754 half-precision quantization emulation.
%   Quantizes mantissa to 11 significant bits (10 stored + 1 implicit).
    halfMax = 65504;
    x = max(min(x, halfMax), -halfMax);

    sgn = sign(x);
    absX = abs(x);

    exponent = floor(log2(absX + (absX == 0)));
    quantum = 2.^(exponent - 10);
    out = sgn .* round(absX ./ quantum) .* quantum;
    out(x == 0) = 0;
end
