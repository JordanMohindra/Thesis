function metrics = evaluateMetrics(detectionListRef, detectionListTest, rdMapRef, rdMapTest, compressionRatio, fullScaleRefPower)
% EVALUATEMETRICS Calculates all evaluation metrics from Section 3.4.2.
%   Metrics: CR, FN%, FP%, Noise Floor Estimation (dBFS), SNR (dB)
%
%   The noise floor and SNR are expressed in dBFS (dB relative to full-scale).
%   The full-scale reference power is the NCI output for a sinusoid at the
%   maximum ADC amplitude, processed through the full chain.
%
%   Input:
%     detectionListRef   - logical mask from reference (FP16) path
%     detectionListTest  - logical mask from test path
%     rdMapRef           - Range-Doppler map from reference path
%     rdMapTest          - Range-Doppler map from test path
%     compressionRatio   - CR value for this algorithm
%     fullScaleRefPower  - power of a full-scale sinusoid after full chain (0 dBFS reference)
%
%   Output:
%     metrics - struct with .CR, .FN_pct, .FP_pct, .NF_dBFS, .SNR_dB

    % --- Compression Ratio ---
    metrics.CR = compressionRatio;

    % --- False Negatives and False Positives ---
    [fp, fn] = comparator(detectionListRef, detectionListTest);
    totalRefDetections = sum(detectionListRef(:));

    if totalRefDetections > 0
        metrics.FN_pct = (fn / totalRefDetections) * 100;
        metrics.FP_pct = (fp / totalRefDetections) * 100;
    else
        metrics.FN_pct = 0;
        metrics.FP_pct = 0;
    end

    % --- Convert RD map to dBFS ---
    rdMapTestDBFS = 10 * log10(rdMapTest / fullScaleRefPower + eps);

    % --- Noise Floor Estimation (dBFS) ---
    % "The noise floor is calculated by taking the mean of the noisy part of the signal in dB"
    % Expand detection mask to exclude vicinity of peaks (avoid sidelobes)
    se = ones(5, 5);
    expandedDetections = logical(conv2(double(detectionListTest), se, 'same'));
    noiseMask = ~expandedDetections;

    noiseValues = rdMapTestDBFS(noiseMask);
    metrics.NF_dBFS = mean(noiseValues);

    % --- SNR (dB) ---
    % "snr = signalRMSdB - noiseRMSdB where noiseRMSdB equals the noise floor"
    % "The signal is taken from the detected peaks"
    if any(detectionListTest(:))
        signalValues = rdMapTest(detectionListTest);
        signalRMSdBFS = 10 * log10(mean(signalValues) / fullScaleRefPower + eps);
    else
        signalRMSdBFS = metrics.NF_dBFS;
    end

    metrics.SNR_dB = signalRMSdBFS - metrics.NF_dBFS;
end
