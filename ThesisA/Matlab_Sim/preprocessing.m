function preprocessedData = preprocessing(rawADC, config)
% PREPROCESSING Shifts ADC data to 32-bit full-scale and applies Hanning window.
%   As described in Section 3.2.1 of Kiem's thesis:
%   1. Shift to full-scale: left-shift by (16 - bitWidth + 16) bits
%   2. Windowing: Hanning window with length = numSamples
%
%   Input:
%     rawADC - int32 matrix [numSamples x numRamps x numRxChannels]
%     config - struct with .bitWidth, .numSamples, .numRamps, .numRxChannels
%
%   Output:
%     preprocessedData - double matrix [numSamples x numRamps x numRxChannels]

    shiftAmount = 16 - config.bitWidth + 16;
    fullScaleData = double(rawADC) * (2^shiftAmount);

    hanningWin = hanning(config.numSamples);

    preprocessedData = fullScaleData .* hanningWin;
end
