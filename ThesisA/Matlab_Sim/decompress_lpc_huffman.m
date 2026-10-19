function fx16Data = decompress_lpc_huffman(compressedData)
% DECOMPRESS_LPC_HUFFMAN Decompresses LPC + Huffman encoded data.
%   Reconstructs the original int16 data by reversing the 2nd-order
%   Linear Predictive Coding (LPC) applied across the slow-time dimension:
%     x[m] = d[m] + round(a1*x[m-L] + a2*x[m-2L])
%   with L = compressedData.lag (see compress_lpc_huffman).
%
%   Input:
%     compressedData - struct from compress_lpc_huffman
%
%   Output:
%     fx16Data - complex double, int16 values divided by .scaleFactor

    diffReal = double(compressedData.diffReal);
    diffImag = double(compressedData.diffImag);
    if isfield(compressedData, 'lag'), L = compressedData.lag; else, L = 1; end

    [nRangeBins, nRamps, nRx] = size(diffReal);

    realData = zeros(nRangeBins, nRamps, nRx);
    imagData = zeros(nRangeBins, nRamps, nRx);

    for rx = 1:nRx
        a1r = compressedData.a1_real(:, rx);  a2r = compressedData.a2_real(:, rx);
        a1i = compressedData.a1_imag(:, rx);  a2i = compressedData.a2_imag(:, rx);
        for m = 1:nRamps
            % previous ramps of the same transmitter (0 before the first)
            if m > L,     r1 = realData(:, m-L, rx);   i1 = imagData(:, m-L, rx);   else, r1 = 0; i1 = 0; end
            if m > 2 * L, r2 = realData(:, m-2*L, rx); i2 = imagData(:, m-2*L, rx); else, r2 = 0; i2 = 0; end
            realData(:, m, rx) = wrap_int16(diffReal(:, m, rx) + round(a1r .* r1 + a2r .* r2));
            imagData(:, m, rx) = wrap_int16(diffImag(:, m, rx) + round(a1i .* i1 + a2i .* i2));
        end
    end

    fx16Data = complex(realData / compressedData.scaleFactor, ...
                       imagData / compressedData.scaleFactor);
end

function wrapped = wrap_int16(val)
% WRAP_INT16 Emulate two's complement int16 wraparound arithmetic.
    wrapped = mod(val + 32768, 65536) - 32768;
end
