function outputData = decompress_fp16(compressedData)
% DECOMPRESS_FP16 Converts half-precision data back to double for processing.
%   Reverses the scaling applied during compression.
%   The 2nd stage processing is always performed in double precision.
%
%   Input:
%     compressedData - struct with .real_part, .imag_part, .scaleFactor
%
%   Output:
%     outputData - complex double [numRangeBins x numRamps x numRxChannels]

    realPart = double(compressedData.real_part) / compressedData.scaleFactor;
    imagPart = double(compressedData.imag_part) / compressedData.scaleFactor;

    outputData = complex(realPart, imagPart);
end
