function outputData = decompress_drhe_fp16(compressedData)
% DECOMPRESS_DRHE_FP16 Inverse of COMPRESS_DRHE_FP16.
%   Reconstructs half-precision range-FFT samples from DRHE residuals, then
%   rescales to double for second-stage processing (same as decompress_fp16).
%
%   Input:
%     compressedData - struct from compress_drhe_fp16
%
%   Output:
%     outputData - complex double [numRangeBins x numRamps x numRxChannels]
%
%   See also: COMPRESS_DRHE_FP16, DECOMPRESS_FP16.

    alpha = compressedData.alpha;
    beta  = compressedData.beta;
    residualScale = compressedData.residualScale;
    scaleFactor   = compressedData.scaleFactor;

    diffReal = double(compressedData.diffReal);
    diffImag = double(compressedData.diffImag);

    [nRangeBins, nRamps, nRx] = size(diffReal);

    reconReal = zeros(nRangeBins, nRamps, nRx);
    reconImag = zeros(nRangeBins, nRamps, nRx);

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

            re = quantize_half(pred_re + diffReal(:, m, rx) * residualScale);
            im = quantize_half(pred_im + diffImag(:, m, rx) * residualScale);

            reconReal(:, m, rx) = re;
            reconImag(:, m, rx) = im;

            curr_mag   = sqrt(re.^2 + im.^2);
            curr_phase = atan2(im, re);

            prev_prev_phase = prev_phase;
            prev_phase      = curr_phase;
            prev_phase_pred = phase_pred;
            prev_mag        = curr_mag;
            prev_mag_pred   = mag_pred;
        end
    end

    outputData = complex(reconReal / scaleFactor, reconImag / scaleFactor);
end

%% ----------------------------------------------------------------------- %%
function p = wrap_phase(phase_pred)
    p = phase_pred;
    p(p > pi)  = p(p > pi)  - 2*pi;
    p(p < -pi) = p(p < -pi) + 2*pi;
end
