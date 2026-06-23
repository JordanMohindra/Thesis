function detectionMask = peakDetection(rdMap, dopplerGuard)
% PEAKDETECTION Detects targets using local maxima + global noise threshold.
%   As described in Section 3.2.1 of Kiem's thesis:
%   A combination of local maxima detection with global thresholding
%   based on noise estimation.
%
%   Input:
%     rdMap        - 2D Range-Doppler map (power) [numRangeBins x numDopplerBins]
%     dopplerGuard - (optional) number of Doppler bins on each side of the
%                    zero-Doppler (DC) column to exclude from detection. This
%                    models standard stationary-clutter rejection: strong
%                    zero-Doppler clutter is not reported as moving targets.
%                    Default 0 (no exclusion).
%
%   Output:
%     detectionMask - logical mask of detected peaks [numRangeBins x numDopplerBins]

    if nargin < 2 || isempty(dopplerGuard)
        dopplerGuard = 0;
    end

    rdMapDB = 10 * log10(rdMap + eps);

    % Noise floor estimation: mean of lower 75% of sorted values
    sortedVals = sort(rdMapDB(:));
    numBins = numel(sortedVals);
    noiseRegion = sortedVals(1:round(0.75 * numBins));
    noiseFloorDB = mean(noiseRegion);

    % Threshold: noise floor + margin
    thresholdDB = noiseFloorDB + 15;

    aboveThreshold = rdMapDB > thresholdDB;

    % Local maxima detection (8-connected neighbourhood)
    [nRows, nCols] = size(rdMap);
    localMaxMask = false(nRows, nCols);

    for r = 2:(nRows-1)
        for c = 2:(nCols-1)
            neighbourhood = rdMapDB(r-1:r+1, c-1:c+1);
            centerVal = rdMapDB(r, c);
            neighbourhood(2, 2) = -Inf;
            if centerVal > max(neighbourhood(:))
                localMaxMask(r, c) = true;
            end
        end
    end

    detectionMask = aboveThreshold & localMaxMask;

    % --- Stationary-clutter (zero-Doppler) rejection ---
    % Blank out a guard band of Doppler bins around DC (column 1, with FFT
    % wraparound at the last columns) so correlated low-Doppler clutter is not
    % counted as detections.
    if dopplerGuard > 0
        nCols = size(rdMap, 2);
        g = min(dopplerGuard, floor((nCols - 1) / 2));
        detectionMask(:, 1:(1 + g)) = false;             % DC and +Doppler side
        detectionMask(:, (nCols - g + 1):nCols) = false; % -Doppler side (wraparound)
    end
end
