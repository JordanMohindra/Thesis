function [detectionList, rdMap, dopplerFFTData] = secondStageProcessing(rangeData, config)
% SECONDSTAGEPROCESSING Performs 2nd stage radar signal processing.
%   As described in Section 3.2.1 of Kiem's thesis:
%   1. Doppler FFT with Hanning window over the Doppler dimension, scaled by 1/numRamps
%   2. Non-Coherent Integration (NCI) across all RX channels
%   3. Peak detection (local maxima + global threshold based on noise estimation)
%
%   Input:
%     rangeData - complex matrix [numRangeBins x numRamps x numRxChannels]
%     config    - struct with .numRamps, .numRxChannels
%
%   Output:
%     detectionList  - logical mask [numRangeBins x numRamps]
%     rdMap          - Range-Doppler map after NCI (power) [numRangeBins x numRamps]
%     dopplerFFTData - complex Doppler FFT output [numRangeBins x numRamps x numRxChannels]

    nRamps = config.numRamps;
    nRx    = config.numRxChannels;

    % --- Doppler FFT with Hanning windowing ---
    dopplerWin = hanning(nRamps)';
    nRangeBins = size(rangeData, 1);

    dopplerFFTData = zeros(size(rangeData));
    for rx = 1:nRx
        windowed = rangeData(:, :, rx) .* repmat(dopplerWin, nRangeBins, 1);
        dopplerFFTData(:, :, rx) = fft(windowed, nRamps, 2) / nRamps;
    end

    % --- Non-Coherent Integration (NCI) across RX channels ---
    rdMap = zeros(nRangeBins, nRamps);
    for rx = 1:nRx
        rdMap = rdMap + abs(dopplerFFTData(:, :, rx)).^2;
    end

    % --- Peak Detection ---
    if isfield(config, 'dopplerGuardBins')
        detectionList = peakDetection(rdMap, config.dopplerGuardBins);
    else
        detectionList = peakDetection(rdMap);
    end
end
