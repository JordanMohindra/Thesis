function outputData = decompress_fx16(compressedData)
% DECOMPRESS_FX16 Converts int16 fixed-point data back to double.
%   Reverses the quantization by dividing by the stored scale factor.
%
%   Input:
%     compressedData - struct with .real_part (int16), .imag_part (int16),
%                      .scaleFactor
%
%   Output:
%     outputData - complex double [numRangeBins x numRamps x numRxChannels]

    realPart = double(compressedData.real_part) / compressedData.scaleFactor;
    imagPart = double(compressedData.imag_part) / compressedData.scaleFactor;

    outputData = realPart + 1j * imagPart;
end
