function fx16Data = decompress_lpc_huffman(compressedData)
% DECOMPRESS_LPC_HUFFMAN Decompresses LPC + Huffman encoded data.
%   Reconstructs the original int16 data by reversing the 2nd-order
%   Linear Predictive Coding (LPC) applied across the slow-time dimension.
%
%   Input:
%     compressedData - struct from compress_lpc_huffman
%
%   Output:
%     fx16Data - struct with .real_part (int16), .imag_part (int16),
%                and .scaleFactor.

    diffReal = double(compressedData.diffReal);
    diffImag = double(compressedData.diffImag);
    
    a1_real  = compressedData.a1_real;
    a2_real  = compressedData.a2_real;
    a1_imag  = compressedData.a1_imag;
    a2_imag  = compressedData.a2_imag;
    
    [nRangeBins, nRamps, nRx] = size(diffReal);
    
    realData = zeros(nRangeBins, nRamps, nRx);
    imagData = zeros(nRangeBins, nRamps, nRx);

    for rx = 1:nRx
        for n = 1:nRangeBins
            a1_r = a1_real(n, rx);
            a2_r = a2_real(n, rx);
            a1_i = a1_imag(n, rx);
            a2_i = a2_imag(n, rx);
            
            prev1_r = 0; prev2_r = 0;
            prev1_i = 0; prev2_i = 0;
            
            for m = 1:nRamps
                % Retrieve the encoded residual
                d_r = diffReal(n, m, rx);
                d_i = diffImag(n, m, rx);
                
                % Compute the predicted value
                pred_r = a1_r * prev1_r + a2_r * prev2_r;
                pred_i = a1_i * prev1_i + a2_i * prev2_i;
                
                % Reconstruct the original sample
                curr_r = wrap_int16(d_r + round(pred_r));
                curr_i = wrap_int16(d_i + round(pred_i));
                
                realData(n, m, rx) = curr_r;
                imagData(n, m, rx) = curr_i;
                
                % Update state
                prev2_r = prev1_r; prev1_r = curr_r;
                prev2_i = prev1_i; prev1_i = curr_i;
            end
        end
    end
    
    fx16Data = complex(double(realData) / compressedData.scaleFactor, ...
                       double(imagData) / compressedData.scaleFactor);
end

function wrapped = wrap_int16(val)
% WRAP_INT16 Emulate two's complement int16 wraparound arithmetic.
    wrapped = mod(val + 32768, 65536) - 32768;
end
