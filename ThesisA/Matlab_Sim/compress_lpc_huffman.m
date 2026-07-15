function compressedData = compress_lpc_huffman(fx16Data, config)
% COMPRESS_LPC_HUFFMAN Linear Predictive Coding + Huffman compression.
%   Implements an LPC predictor across the slow-time (Doppler) dimension.
%   For each range bin and Rx channel, a 2nd-order predictor is computed
%   using the Yule-Walker equations. The prediction residual is encoded
%   using a static Huffman dictionary (borrowed from DRHE for radar data).
%
%   Input:
%     fx16Data - struct from compress_fx16 with .real_part (int16),
%                .imag_part (int16), .scaleFactor
%     config   - struct with .numRamps, .numRxChannels
%
%   Output:
%     compressedData - struct with residuals, LPC coefficients, and metrics.

    realData = double(fx16Data.real_part);
    imagData = double(fx16Data.imag_part);

    [nRangeBins, nRamps, nRx] = size(realData);
    huffLengths = lpc_huffman_lengths();

    diffReal = zeros(nRangeBins, nRamps, nRx);
    diffImag = zeros(nRangeBins, nRamps, nRx);
    
    % Store the 2nd-order LPC coefficients (a1, a2) for real and imag
    a1_real = zeros(nRangeBins, nRx);
    a2_real = zeros(nRangeBins, nRx);
    a1_imag = zeros(nRangeBins, nRx);
    a2_imag = zeros(nRangeBins, nRx);

    totalBits = 0;

    for rx = 1:nRx
        for n = 1:nRangeBins
            % Extract the sequence across ramps
            seq_r = squeeze(realData(n, :, rx));
            seq_i = squeeze(imagData(n, :, rx));
            
            % Compute LPC coefficients for Real part
            [a1_r, a2_r] = compute_lpc_order2(seq_r);
            a1_real(n, rx) = a1_r;
            a2_real(n, rx) = a2_r;
            
            % Compute LPC coefficients for Imag part
            [a1_i, a2_i] = compute_lpc_order2(seq_i);
            a1_imag(n, rx) = a1_i;
            a2_imag(n, rx) = a2_i;
            
            % Apply prediction and compute residuals
            prev1_r = 0; prev2_r = 0;
            prev1_i = 0; prev2_i = 0;
            
            for m = 1:nRamps
                curr_r = seq_r(m);
                curr_i = seq_i(m);
                
                pred_r = a1_r * prev1_r + a2_r * prev2_r;
                pred_i = a1_i * prev1_i + a2_i * prev2_i;
                
                % The residual needs to fit in the same data type
                d_r = wrap_int16(curr_r - round(pred_r));
                d_i = wrap_int16(curr_i - round(pred_i));
                
                diffReal(n, m, rx) = d_r;
                diffImag(n, m, rx) = d_i;
                
                % Update state
                prev2_r = prev1_r; prev1_r = curr_r;
                prev2_i = prev1_i; prev1_i = curr_i;
            end
        end
    end
    
    % Compute bits for the Huffman-encoded residuals
    totalBits = totalBits + sum(lpc_encode_bits(diffReal(:), huffLengths));
    totalBits = totalBits + sum(lpc_encode_bits(diffImag(:), huffLengths));
    
    % Add overhead for the LPC coefficients (assume 16-bit float/fixed per coeff)
    % 4 coefficients (a1_r, a2_r, a1_i, a2_i) per range bin per Rx channel
    overheadBits = nRangeBins * nRx * 4 * 16;
    totalBits = totalBits + overheadBits;

    inputBits = numel(realData) * 2 * 16;

    compressedData.diffReal    = int16(diffReal);
    compressedData.diffImag    = int16(diffImag);
    compressedData.a1_real     = a1_real;
    compressedData.a2_real     = a2_real;
    compressedData.a1_imag     = a1_imag;
    compressedData.a2_imag     = a2_imag;
    
    compressedData.totalBits   = totalBits;
    compressedData.inputBits   = inputBits;
    compressedData.CR          = inputBits / totalBits;
    compressedData.scaleFactor = fx16Data.scaleFactor;
    compressedData.format      = 'lpc_huffman';
end


function [a1, a2] = compute_lpc_order2(seq)
% COMPUTE_LPC_ORDER2 Computes 2nd-order LPC coefficients using Yule-Walker.
    N = length(seq);
    if N < 3
        a1 = 0; a2 = 0; return;
    end
    
    R0 = sum(seq.^2);
    R1 = sum(seq(1:N-1) .* seq(2:N));
    R2 = sum(seq(1:N-2) .* seq(3:N));
    
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
% LPC_ENCODE_BITS Compute the number of bits needed to encode each value.
%   Uses the S4 region + APPEND (S4 bits) + Huffman code logic.
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


function lengths = lpc_huffman_lengths()
% LPC_HUFFMAN_LENGTHS Fixed Huffman dictionary lengths (from DRHE).
    lengths = [4, 3, 2, 2, 2, 5, 6, 7, 8, 9, 10, 11, 14, 14, 13, 12];
end
