function compressedData = compress_lpc_huffman(fx16Data, config)
% COMPRESS_LPC_HUFFMAN Linear Predictive Coding + Huffman compression.
%   Implements an LPC predictor across the slow-time (Doppler) dimension.
%   For each range bin and Rx channel, a 2nd-order predictor is computed
%   using the Yule-Walker equations. The prediction residual is encoded
%   using a static S4 + Huffman dictionary (the same format as DRHE).
%
%   Prediction lags (config.predLag = L):
%     x_hat[m] = a1 * x[m - L] + a2 * x[m - 2L]
%   In a TDM-MIMO radar ramp m - nTx is the previous ramp of the same
%   transmitter, so L = nTx keeps the predictor on one antenna. Default L:
%     config.predLag if set, else config.nTx if set, else 1 (single TX).
%
%   Huffman dictionary (config.huffLengthsLPC): 16 code lengths for
%   S4 = 0..15. Default: Kiem's table, huffman_tables('kiem').
%
%   Input:
%     fx16Data - struct from compress_fx16 with .real_part (int16),
%                .imag_part (int16), .scaleFactor
%     config   - struct (optional fields .predLag, .nTx, .huffLengthsLPC)
%
%   Output:
%     compressedData - struct with residuals, LPC coefficients, and metrics.
%                      .residualBits and .overheadBits split the total.

    realData = double(fx16Data.real_part);
    imagData = double(fx16Data.imag_part);

    [nRangeBins, nRamps, nRx] = size(realData);

    lag = prediction_lag(config);
    if isfield(config, 'huffLengthsLPC') && ~isempty(config.huffLengthsLPC)
        huffLengths = config.huffLengthsLPC(:).';
    else
        huffLengths = huffman_tables('kiem');
    end

    diffReal = zeros(nRangeBins, nRamps, nRx);
    diffImag = zeros(nRangeBins, nRamps, nRx);

    % Store the 2nd-order LPC coefficients (a1, a2) for real and imag
    a1_real = zeros(nRangeBins, nRx);
    a2_real = zeros(nRangeBins, nRx);
    a1_imag = zeros(nRangeBins, nRx);
    a2_imag = zeros(nRangeBins, nRx);

    for rx = 1:nRx
        for n = 1:nRangeBins
            seq_r = realData(n, :, rx);
            seq_i = imagData(n, :, rx);

            [a1_r, a2_r] = compute_lpc_order2(seq_r, lag);
            [a1_i, a2_i] = compute_lpc_order2(seq_i, lag);
            a1_real(n, rx) = a1_r;  a2_real(n, rx) = a2_r;
            a1_imag(n, rx) = a1_i;  a2_imag(n, rx) = a2_i;

            diffReal(n, :, rx) = wrap_int16(seq_r - round(lpc_predict(seq_r, a1_r, a2_r, lag)));
            diffImag(n, :, rx) = wrap_int16(seq_i - round(lpc_predict(seq_i, a1_i, a2_i, lag)));
        end
    end

    % Huffman-coded residuals
    residualBits = sum(lpc_encode_bits(diffReal(:), huffLengths)) + ...
                   sum(lpc_encode_bits(diffImag(:), huffLengths));

    % Side information: 4 coefficients (a1_r, a2_r, a1_i, a2_i) of 16 bits
    % per range bin per Rx channel
    overheadBits = nRangeBins * nRx * 4 * 16;
    totalBits = residualBits + overheadBits;

    inputBits = numel(realData) * 2 * 16;

    compressedData.diffReal     = int16(diffReal);
    compressedData.diffImag     = int16(diffImag);
    compressedData.a1_real      = a1_real;
    compressedData.a2_real      = a2_real;
    compressedData.a1_imag      = a1_imag;
    compressedData.a2_imag      = a2_imag;
    compressedData.lag          = lag;
    compressedData.huffLengths  = huffLengths;
    compressedData.residualBits = residualBits;
    compressedData.overheadBits = overheadBits;
    compressedData.totalBits    = totalBits;
    compressedData.inputBits    = inputBits;
    compressedData.CR           = inputBits / totalBits;
    compressedData.scaleFactor  = fx16Data.scaleFactor;
    compressedData.format       = 'lpc_huffman';
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


function pred = lpc_predict(seq, a1, a2, L)
% x_hat[m] = a1*x[m-L] + a2*x[m-2L], with x = 0 before the first ramp
    N = numel(seq);
    xm1 = [zeros(1, min(L, N)),     seq(1:max(N - L, 0))];
    xm2 = [zeros(1, min(2 * L, N)), seq(1:max(N - 2 * L, 0))];
    pred = a1 * xm1 + a2 * xm2;
end


function [a1, a2] = compute_lpc_order2(seq, L)
% COMPUTE_LPC_ORDER2 2nd-order LPC coefficients at lags L and 2L (Yule-Walker).
    N = length(seq);
    if N <= 2 * L
        a1 = 0; a2 = 0; return;
    end

    R0 = sum(seq.^2);
    R1 = sum(seq(1:N-L)   .* seq(1+L:N));
    R2 = sum(seq(1:N-2*L) .* seq(1+2*L:N));

    det = R0^2 - R1^2;
    if det == 0
        a1 = 0; a2 = 0;
    else
        a1 = (R1 * (R0 - R2)) / det;
        a2 = (R0 * R2 - R1^2) / det;

        % Constrain coefficients to ensure stability
        if abs(a2) >= 1 || abs(a1) >= (1 - a2)
            a1 = 0; a2 = 0;
        end
    end
end


function wrapped = wrap_int16(val)
% WRAP_INT16 Emulate two's complement int16 wraparound arithmetic.
    wrapped = mod(val + 32768, 65536) - 32768;
end


function bits = lpc_encode_bits(values, huffLengths)
% LPC_ENCODE_BITS Bits per value: Huffman code for S4 + S4 APPEND bits.
    s4 = s4_region(values);
    bits = reshape(huffLengths(s4 + 1), size(s4)) + s4;
end
