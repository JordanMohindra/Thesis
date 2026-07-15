function rawADC = generateSyntheticADC(config)
% GENERATESYNTHETICADC Generates a synthetic raw ADC data cube.
%   Simulates FMCW radar targets at specified range/Doppler bins with AWGN.
%   Follows the simulated data specification from Kiem's thesis, Table 3.2.
%
%   Target amplitudes are fractions of ADC full-scale (e.g. 0.8 = 80% of max).
%   Noise level is back-calculated from the desired post-NCI noise floor (dBFS).
%
%   Input:
%     config - struct with fields:
%       .numSamples, .numRamps, .numRxChannels, .bitWidth
%       .numTargets, .targetRangeBins, .targetDopplerBins, .targetAmplitudes
%       .noiseLevelDB  (desired noise floor after NCI in dBFS)
%
%   Output:
%     rawADC - int32 matrix [numSamples x numRamps x numRxChannels]

    nSamp = config.numSamples;
    nRamp = config.numRamps;
    nRx   = config.numRxChannels;

    maxADCVal = 2^(config.bitWidth - 1) - 1;

    % --- Anti-clipping guard ---
    % The targets are superimposed sinusoids with random phases. The
    % instantaneous sum is approximately Gaussian with RMS = sqrt(0.5*sum(A^2));
    % its peak is ~crest * RMS (crest ~ 4-5 sigma). The old worst-case bound
    % sum(A) is far too pessimistic once there are many returns (e.g. a clutter
    % field), so we use the statistical peak estimate instead and only scale the
    % amplitudes down if that estimate would overdrive the ADC. This keeps the
    % anti-clip guard from silently rescaling (and de-calibrating) dense scenes.
    if isfield(config, 'fullScaleBackoff')
        backoff = config.fullScaleBackoff;
    else
        backoff = 0.9;
    end
    if isfield(config, 'crestFactor')
        crest = config.crestFactor;
    else
        crest = 4.5;
    end
    amplitudes = config.targetAmplitudes;
    estPeak = crest * sqrt(0.5 * sum(amplitudes.^2));
    if estPeak > backoff
        scale = backoff / estPeak;
        amplitudes = amplitudes * scale;
        fprintf(['  [ADC Gen] WARNING: estimated peak %.2f (> %.2f full-scale).\n' ...
                 '            Scaled by %.3f to avoid ADC clipping and spur generation.\n'], ...
                 estPeak, backoff, scale);
    end

    % --- Compute ADC noise sigma from desired post-NCI noise floor ---
    % After full chain: Preprocessing -> Range FFT(/N) -> Doppler FFT(Hanning, /M) -> NCI
    %
    % NCI noise power = nRx * sigma_shifted^2 * sum(hannR.^2)/N^2 * sum(hannD.^2)/M^2
    % P_ref = nRx * (maxADCVal * 2^shift * sum(hannR)/(2N) * sum(hannD)/M)^2
    %
    % NF_linear = 10*log10(NCI_noise / P_ref)
    % We target NF_linear = noiseLevelDB (with some empirical adjustment for dB-averaging)
    shift = 16 - config.bitWidth + 16;
    hannR = hann(nSamp);
    hannD = hann(nRamp);

    sumHannR2 = sum(hannR.^2);
    sumHannD2 = sum(hannD.^2);
    sumHannR  = sum(hannR);
    sumHannD  = sum(hannD);

    % Full-scale reference power (0 dBFS)
    peakR = maxADCVal * 2^shift * sumHannR / (2 * nSamp);
    peakD = peakR * sumHannD / nRamp;
    P_ref = nRx * peakD^2;

    % Solve for sigma_shifted from: NF = 10*log10(nRx * sigma^2 * G / P_ref)
    % where G = sumHannR2/N^2 * sumHannD2/M^2 is the noise processing gain factor
    noiseGainFactor = sumHannR2 / nSamp^2 * sumHannD2 / nRamp^2;
    NCI_noise_target = P_ref * 10^(config.noiseLevelDB / 10);
    sigma_shifted_sq = NCI_noise_target / (nRx * noiseGainFactor);

    sigma_shifted = sqrt(sigma_shifted_sq);
    noiseSigmaADC = sigma_shifted / (2^shift);

    fprintf('  [ADC Gen] sigma_ADC = %.4f (%.1f dB below full-scale)\n', ...
        noiseSigmaADC, 20*log10(noiseSigmaADC / maxADCVal));

    n = (0:nSamp-1)';
    m = (0:nRamp-1);

    rawADC = zeros(nSamp, nRamp, nRx);

    for rx = 1:nRx
        signal = zeros(nSamp, nRamp);

        for t = 1:config.numTargets
            rangeBin   = config.targetRangeBins(t);
            dopplerBin = config.targetDopplerBins(t);
            amplitude  = amplitudes(t) * maxADCVal;

            rangeFreq   = (rangeBin - 1) / nSamp;
            dopplerFreq = (dopplerBin - 1) / nRamp;

            phaseOffset = 2 * pi * rand();

            signal = signal + amplitude * ...
                cos(2*pi*rangeFreq*n + 2*pi*dopplerFreq*m + phaseOffset);
        end

        % --- Receiver / clutter noise ---
        % White AWGN is uncorrelated ramp-to-ramp, so DRHE (which predicts each
        % ramp from the previous one) cannot compress it: at a given noise floor
        % CR ~ 1. REAL radar noise has structure (oscillator phase noise, slow
        % clutter, multipath ripple). The CORRELATED parts ARE compressible by
        % DRHE. generateNoise() exposes several correlation models so we can
        % test how much of Kiem's "real-data" CR comes from non-AWGN structure.
        %
        % config.noiseType   : 'white' (default) | 'ar1_slow' | 'ar1_fast'
        %                       | 'colored_slow' | 'pink_slow' | 'mixed'
        % config.noiseParams : struct with model-specific params, e.g.
        %     .rho   AR(1) coefficient in [0,1) for ar1_* and mixed
        %     .bw    cutoff fraction for colored_slow
        %     .alpha mixed: fraction of variance that is correlated
        % config.noiseCorr   : (legacy) scalar rho. If set and noiseType
        %                      missing, behaves as ar1_slow with this rho.
        if isfield(config, 'noiseType') && ~isempty(config.noiseType)
            nType = config.noiseType;
        elseif isfield(config, 'noiseCorr') && config.noiseCorr > 0
            nType = 'ar1_slow';
        else
            nType = 'white';
        end
        if isfield(config, 'noiseParams')
            nParams = config.noiseParams;
        elseif isfield(config, 'noiseCorr')
            nParams = struct('rho', config.noiseCorr);
        else
            nParams = struct();
        end
        noise = generateNoise(nType, nSamp, nRamp, noiseSigmaADC, nParams);
        signal = signal + noise;

        signal = max(min(signal, maxADCVal), -maxADCVal);

        rawADC(:, :, rx) = round(signal);
    end

    rawADC = int32(rawADC);

    % --- Clipping report ---
    % Heavy clipping (> ~1%) indicates the targets/noise are overdriving the
    % ADC and will smear the range-Doppler map with intermodulation spurs.
    clipFraction = 100 * sum(abs(rawADC(:)) >= maxADCVal) / numel(rawADC);
    fprintf('  [ADC Gen] clipped samples = %.3f%%', clipFraction);
    if clipFraction > 1
        fprintf('  <-- WARNING: high clipping, expect spur "grass" in RD map\n');
    else
        fprintf('  (clean)\n');
    end
end
