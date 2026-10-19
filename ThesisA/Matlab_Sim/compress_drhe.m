function compressedData = compress_drhe(fx16Data, config)
% COMPRESS_DRHE DRHE compression (Doppler Redundancy Hybrid Encoding).
%   Implements the final DRHE algorithm from Kiem's thesis (Section 3.5.3):
%   1. Model prediction using IIR filters for magnitude and phase
%   2. Compute difference between actual and predicted (Cartesian)
%   3. Encode differences using S4 region + Huffman coding
%
%   The algorithm exploits Doppler-dimension redundancy: for each range bin,
%   each ramp is predicted from earlier ramps of the SAME transmitter, and
%   only the small differences are encoded.
%
%   Prediction lag (config.predLag):
%     In a TDM-MIMO radar the transmitters fire in turn, so the ramp axis is
%     ramp = chirpLoop * nTx + tx. The previous ramp of the same transmitter
%     is nTx ramps back, so the predictor keeps one state per transmitter and
%     predicts ramp m from ramp m - nTx. Default lag:
%       config.predLag   if set
%       config.nTx       if set (ColoRadar loader: 12)
%       1                otherwise (single-TX radar, e.g. Kiem's data)
%
%   Huffman dictionary (config.huffLengthsDRHE):
%     16 code lengths for S4 = 0..15. Default: Kiem's Appendix A table
%     (huffman_tables('kiem')). See huffman_tables.m for the re-derived one.
%
%   DRHE operates on int16 (FX16) data with two's complement wraparound.
%   After decompression, the int16 values are restored losslessly.
%
%   Parameters: alpha=0.6 (magnitude), beta=0.4 (phase) - Table 4.4
%
%   Input:
%     fx16Data - struct from compress_fx16 with .real_part (int16),
%                .imag_part (int16), .scaleFactor
%     config   - struct (optional fields .predLag, .nTx, .huffLengthsDRHE)
%
%   Output:
%     compressedData - struct with .diffReal, .diffImag, .totalBits,
%                      .inputBits, .CR, .scaleFactor, .lag, .huffLengths

    alpha = 0.6;
    beta  = 0.4;

    realData = double(fx16Data.real_part);
    imagData = double(fx16Data.imag_part);

    [nRangeBins, nRamps, nRx] = size(realData);

    lag = prediction_lag(config);
    if isfield(config, 'huffLengthsDRHE') && ~isempty(config.huffLengthsDRHE)
        huffLengths = config.huffLengthsDRHE(:).';
    else
        huffLengths = huffman_tables('kiem');
    end

    diffReal = zeros(nRangeBins, nRamps, nRx);
    diffImag = zeros(nRangeBins, nRamps, nRx);
    totalBits = 0;

    for rx = 1:nRx
        % one predictor state per transmitter (column t = 1..lag)
        prev_mag_pred    = zeros(nRangeBins, lag);
        prev_mag         = zeros(nRangeBins, lag);
        prev_phase_pred  = zeros(nRangeBins, lag);
        prev_phase       = zeros(nRangeBins, lag);
        prev_prev_phase  = zeros(nRangeBins, lag);

        for m = 1:nRamps
            t  = mod(m - 1, lag) + 1;
            re = realData(:, m, rx);
            im = imagData(:, m, rx);

            curr_mag   = sqrt(re.^2 + im.^2);
            curr_phase = atan2(im, re);

            mag_pred   = alpha * prev_mag_pred(:, t) + (1 - alpha) * prev_mag(:, t);
            phase_pred = beta * prev_phase_pred(:, t) + (2 - beta) * prev_phase(:, t) - prev_prev_phase(:, t);

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

            prev_prev_phase(:, t) = prev_phase(:, t);
            prev_phase(:, t)      = curr_phase;
            prev_phase_pred(:, t) = phase_pred;
            prev_mag(:, t)        = curr_mag;
            prev_mag_pred(:, t)   = mag_pred;
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
    compressedData.lag         = lag;
    compressedData.huffLengths = huffLengths;
    compressedData.format      = 'drhe';
end


function lag = prediction_lag(config)
    if isfield(config, 'predLag') && ~isempty(config.predLag)
        lag = config.predLag;
    elseif isfield(config, 'nTx') && ~isempty(config.nTx)
        lag = config.nTx;
    else
        lag = 1;
    end
end


function wrapped = wrap_int16(val)
% WRAP_INT16 Emulate two's complement int16 wraparound arithmetic.
    wrapped = mod(val + 32768, 65536) - 32768;
end


function bits = drhe_encode_bits(values, huffLengths)
% DRHE_ENCODE_BITS Compute the number of bits needed to encode each value.
%   Each value maps to S4 (region) + APPEND (S4 bits) + Huffman code.
%   Total bits per value = huffman_code_length(S4) + S4
    s4 = s4_region(values);
    bits = reshape(huffLengths(s4 + 1), size(s4)) + s4;
end
