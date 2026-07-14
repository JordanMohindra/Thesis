function compressedData = compress_drhe_fp16(fp16Data, config)
% COMPRESS_DRHE_FP16 DRHE on FP16 (half-precision) range-FFT data.
%   Same Doppler-redundancy predictor as COMPRESS_DRHE (Kiem Section 3.5.3),
%   but operates on the half-precision grid instead of int16 fixed-point.
%   Residuals are quantised to int16 with a frame-level scale and encoded
%   with the same S4 + Huffman bit model as the FX16 DRHE path.
%
%   The encoder uses a synthesis loop: predictor state is advanced from
%   reconstructed half values so it matches DECOMPRESS_DRHE_FP16 exactly.
%
%   See also: DECOMPRESS_DRHE_FP16, COMPRESS_DRHE, COMPRESS_FP16.

    if nargin < 2; config = struct(); end %#ok<NASGU>

    alpha = 0.6;
    beta  = 0.4;

    realData = double(fp16Data.real_part);
    imagData = double(fp16Data.imag_part);

    [nRangeBins, nRamps, nRx] = size(realData);

    % --- Pass 1: estimate residual scale (state from stored half values) --
    maxAbs = 0;
    for rx = 1:nRx
        prev_mag_pred    = zeros(nRangeBins, 1);
        prev_mag         = zeros(nRangeBins, 1);
        prev_phase_pred  = zeros(nRangeBins, 1);
        prev_phase       = zeros(nRangeBins, 1);
        prev_prev_phase  = zeros(nRangeBins, 1);

        for m = 1:nRamps
            re = realData(:, m, rx);
            im = imagData(:, m, rx);

            mag_pred   = alpha * prev_mag_pred + (1 - alpha) * prev_mag;
            phase_pred = beta * prev_phase_pred + (2 - beta) * prev_phase - prev_prev_phase;
            phase_pred = wrap_phase(phase_pred);

            pred_re = quantize_half(mag_pred .* cos(phase_pred));
            pred_im = quantize_half(mag_pred .* sin(phase_pred));

            maxAbs = max(maxAbs, max(abs([re - pred_re; im - pred_im])));

            curr_mag   = sqrt(re.^2 + im.^2);
            curr_phase = atan2(im, re);

            prev_prev_phase = prev_phase;
            prev_phase      = curr_phase;
            prev_phase_pred = phase_pred;
            prev_mag        = curr_mag;
            prev_mag_pred   = mag_pred;
        end
    end

    if maxAbs > 0
        residualScale = maxAbs / 32767;
    else
        residualScale = 1;
    end

    % --- Pass 2: encode with synthesis loop --------------------------------
    diffRealQ = zeros(nRangeBins, nRamps, nRx, 'int16');
    diffImagQ = zeros(nRangeBins, nRamps, nRx, 'int16');

    for rx = 1:nRx
        prev_mag_pred    = zeros(nRangeBins, 1);
        prev_mag         = zeros(nRangeBins, 1);
        prev_phase_pred  = zeros(nRangeBins, 1);
        prev_phase       = zeros(nRangeBins, 1);
        prev_prev_phase  = zeros(nRangeBins, 1);

        for m = 1:nRamps
            mag_pred   = alpha * prev_mag_pred + (1 - alpha) * prev_mag;
            phase_pred = beta * prev_phase_pred + (2 - beta) * prev_phase - prev_prev_phase;
            phase_pred = wrap_phase(phase_pred);

            pred_re = quantize_half(mag_pred .* cos(phase_pred));
            pred_im = quantize_half(mag_pred .* sin(phase_pred));

            target_re = realData(:, m, rx);
            target_im = imagData(:, m, rx);

            d_re = target_re - pred_re;
            d_im = target_im - pred_im;

            diffRealQ(:, m, rx) = int16(round(d_re / residualScale));
            diffImagQ(:, m, rx) = int16(round(d_im / residualScale));

            re = quantize_half(pred_re + double(diffRealQ(:, m, rx)) * residualScale);
            im = quantize_half(pred_im + double(diffImagQ(:, m, rx)) * residualScale);

            curr_mag   = sqrt(re.^2 + im.^2);
            curr_phase = atan2(im, re);

            prev_prev_phase = prev_phase;
            prev_phase      = curr_phase;
            prev_phase_pred = phase_pred;
            prev_mag        = curr_mag;
            prev_mag_pred   = mag_pred;
        end
    end

    huffLengths = drhe_huffman_lengths();
    totalBits = sum(drhe_encode_bits(diffRealQ(:), huffLengths)) ...
              + sum(drhe_encode_bits(diffImagQ(:), huffLengths));

    inputBits = numel(realData) * 2 * 16;

    compressedData.diffReal      = diffRealQ;
    compressedData.diffImag      = diffImagQ;
    compressedData.residualScale = residualScale;
    compressedData.totalBits     = totalBits;
    compressedData.inputBits     = inputBits;
    compressedData.CR            = inputBits / totalBits;
    compressedData.scaleFactor   = fp16Data.scaleFactor;
    compressedData.alpha         = alpha;
    compressedData.beta          = beta;
    compressedData.format        = 'drhe_fp16';
end

%% ----------------------------------------------------------------------- %%
function p = wrap_phase(phase_pred)
    p = phase_pred;
    p(p > pi)  = p(p > pi)  - 2*pi;
    p(p < -pi) = p(p < -pi) + 2*pi;
end

function bits = drhe_encode_bits(values, huffLengths)
    absVal = abs(double(values));
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
    lengths = [4, 3, 2, 2, 2, 5, 6, 7, 8, 9, 10, 11, 14, 14, 13, 12];
end
