function compressedData = compress_drhe(fx16Data, config)
% COMPRESS_DRHE DRHE compression (Doppler Redundancy Hybrid Encoding).
%   Implements the final DRHE algorithm from Kiem's thesis (Section 3.5.3):
%   1. Model prediction using IIR filters for magnitude and phase
%   2. Compute difference between actual and predicted (Cartesian)
%   3. Encode differences using S4 region + Huffman coding
%
%   The algorithm exploits Doppler-dimension redundancy: for each range bin,
%   consecutive ramps are predicted using IIR filters, and only the small
%   differences are encoded.
%
%   DRHE operates on int16 (FX16) data with two's complement wraparound.
%   After decompression, the int16 values are restored losslessly.
%
%   Parameters: alpha=0.6 (magnitude), beta=0.4 (phase) - Table 4.4
%
%   Input:
%     fx16Data - struct from compress_fx16 with .real_part (int16),
%                .imag_part (int16), .scaleFactor
%     config   - struct with .numRamps, .numRxChannels
%
%   Output:
%     compressedData - struct with .diffReal, .diffImag, .totalBits,
%                      .inputBits, .CR, .scaleFactor, .config

    alpha = 0.6;
    beta  = 0.4;

    realData = double(fx16Data.real_part);
    imagData = double(fx16Data.imag_part);

    [nRangeBins, nRamps, nRx] = size(realData);

    huffLengths = drhe_huffman_lengths();

    diffReal = zeros(nRangeBins, nRamps, nRx);
    diffImag = zeros(nRangeBins, nRamps, nRx);
    totalBits = 0;

    for rx = 1:nRx
        prev_mag_pred    = zeros(nRangeBins, 1);
        prev_mag         = zeros(nRangeBins, 1);
        prev_phase_pred  = zeros(nRangeBins, 1);
        prev_phase       = zeros(nRangeBins, 1);
        prev_prev_phase  = zeros(nRangeBins, 1);

        for m = 1:nRamps
            re = realData(:, m, rx);
            im = imagData(:, m, rx);

            curr_mag   = sqrt(re.^2 + im.^2);
            curr_phase = atan2(im, re);

            mag_pred   = alpha * prev_mag_pred + (1 - alpha) * prev_mag;
            phase_pred = beta * prev_phase_pred + (2 - beta) * prev_phase - prev_prev_phase;

            phase_pred(phase_pred > pi)  = phase_pred(phase_pred > pi)  - 2*pi;
            phase_pred(phase_pred < -pi) = phase_pred(phase_pred < -pi) + 2*pi;

            pred_re = round(mag_pred .* cos(phase_pred));
            pred_im = round(mag_pred .* sin(phase_pred));

            d_re = wrap_int16(re - pred_re);
            d_im = wrap_int16(im - pred_im);

            diffReal(:, m, rx) = d_re;
            diffImag(:, m, rx) = d_im;

            totalBits = totalBits + sum(drhe_encode_bits(d_re, huffLengths)) ...
                                  + sum(drhe_encode_bits(d_im, huffLengths));

            prev_prev_phase = prev_phase;
            prev_phase      = curr_phase;
            prev_phase_pred = phase_pred;
            prev_mag        = curr_mag;
            prev_mag_pred   = mag_pred;
        end
    end

    inputBits = numel(realData) * 2 * 16;

    compressedData.diffReal    = int16(diffReal);
    compressedData.diffImag    = int16(diffImag);
    compressedData.totalBits   = totalBits;
    compressedData.inputBits   = inputBits;
    compressedData.CR          = inputBits / totalBits;
    compressedData.scaleFactor = fx16Data.scaleFactor;
    compressedData.alpha       = alpha;
    compressedData.beta        = beta;
    compressedData.format      = 'drhe';
end


function wrapped = wrap_int16(val)
% WRAP_INT16 Emulate two's complement int16 wraparound arithmetic.
    wrapped = mod(val + 32768, 65536) - 32768;
end


function bits = drhe_encode_bits(values, huffLengths)
% DRHE_ENCODE_BITS Compute the number of bits needed to encode each value.
%   Each value maps to S4 (region) + APPEND (S4 bits) + Huffman code.
%   Total bits per value = huffman_code_length(S4) + S4

    absVal = abs(values);
    s4 = zeros(size(values));

    s4(absVal == 0) = 0;
    nonzero = absVal > 0;
    s4(nonzero) = floor(log2(absVal(nonzero))) + 1;
    s4 = min(s4, 15);

    bits = zeros(size(values));
    for i = 0:15
        mask = (s4 == i);
        bits(mask) = huffLengths(i + 1) + i;
    end
end


function lengths = drhe_huffman_lengths()
% DRHE_HUFFMAN_LENGTHS Fixed Huffman dictionary lengths from Appendix A.
%   Index 1-16 corresponds to S4 values 0-15.
    lengths = [4, 3, 2, 2, 2, 5, 6, 7, 8, 9, 10, 11, 14, 14, 13, 12];
end
