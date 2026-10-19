function outputData = decompress_drhe(compressedData)
% DECOMPRESS_DRHE Decompresses DRHE-encoded data using inverse model prediction.
%   Implements the decompression from Kiem's thesis (Section 3.5.4):
%   1. Decode differences (stored losslessly as int16)
%   2. Apply inverse model prediction: X[m,n] = D[m,n] + Prediction[m,n]
%   3. Output is int16 complex data, which is then scaled back to double
%
%   Uses two's complement wraparound arithmetic to match hardware behavior.
%   The model prediction is identical to compression: one predictor state
%   per transmitter (lag = compressedData.lag, see compress_drhe), each
%   initialised to zero and updated with decoded values.
%
%   Input:
%     compressedData - struct from compress_drhe with .diffReal, .diffImag,
%                      .scaleFactor, .alpha, .beta, .lag
%
%   Output:
%     outputData - complex double [numRangeBins x numRamps x numRxChannels]

    alpha = compressedData.alpha;
    beta  = compressedData.beta;
    scaleFactor = compressedData.scaleFactor;
    if isfield(compressedData, 'lag'), lag = compressedData.lag; else, lag = 1; end

    diffReal = double(compressedData.diffReal);
    diffImag = double(compressedData.diffImag);

    [nRangeBins, nRamps, nRx] = size(diffReal);

    reconReal = zeros(nRangeBins, nRamps, nRx);
    reconImag = zeros(nRangeBins, nRamps, nRx);

    for rx = 1:nRx
        prev_mag_pred    = zeros(nRangeBins, lag);
        prev_mag         = zeros(nRangeBins, lag);
        prev_phase_pred  = zeros(nRangeBins, lag);
        prev_phase       = zeros(nRangeBins, lag);
        prev_prev_phase  = zeros(nRangeBins, lag);

        for m = 1:nRamps
            t = mod(m - 1, lag) + 1;
            mag_pred   = alpha * prev_mag_pred(:, t) + (1 - alpha) * prev_mag(:, t);
            phase_pred = beta * prev_phase_pred(:, t) + (2 - beta) * prev_phase(:, t) - prev_prev_phase(:, t);

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

            prev_prev_phase(:, t) = prev_phase(:, t);
            prev_phase(:, t)      = curr_phase;
            prev_phase_pred(:, t) = phase_pred;
            prev_mag(:, t)        = curr_mag;
            prev_mag_pred(:, t)   = mag_pred;
        end
    end

    outputData = complex(reconReal / scaleFactor, reconImag / scaleFactor);
end


function wrapped = wrap_int16(val)
% WRAP_INT16 Emulate two's complement int16 wraparound arithmetic.
    wrapped = mod(val + 32768, 65536) - 32768;
end
