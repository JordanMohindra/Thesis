function outputData = decompress_drhe(compressedData)
% DECOMPRESS_DRHE Decompresses DRHE-encoded data using inverse model prediction.
%   Implements the decompression from Kiem's thesis (Section 3.5.4):
%   1. Decode differences (stored losslessly as int16)
%   2. Apply inverse model prediction: X[m,n] = D[m,n] + Prediction[m,n]
%   3. Output is int16 complex data, which is then scaled back to double
%
%   Uses two's complement wraparound arithmetic to match hardware behavior.
%   The model prediction is identical to compression: initialized to zero,
%   updated with decoded values ramp by ramp.
%
%   Input:
%     compressedData - struct from compress_drhe with .diffReal, .diffImag,
%                      .scaleFactor, .alpha, .beta
%
%   Output:
%     outputData - complex double [numRangeBins x numRamps x numRxChannels]

    alpha = compressedData.alpha;
    beta  = compressedData.beta;
    scaleFactor = compressedData.scaleFactor;

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

            phase_pred(phase_pred > pi)  = phase_pred(phase_pred > pi)  - 2*pi;
            phase_pred(phase_pred < -pi) = phase_pred(phase_pred < -pi) + 2*pi;

            pred_re = round(mag_pred .* cos(phase_pred));
            pred_im = round(mag_pred .* sin(phase_pred));

            re = wrap_int16(diffReal(:, m, rx) + pred_re);
            im = wrap_int16(diffImag(:, m, rx) + pred_im);

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


function wrapped = wrap_int16(val)
% WRAP_INT16 Emulate two's complement int16 wraparound arithmetic.
    wrapped = mod(val + 32768, 65536) - 32768;
end
