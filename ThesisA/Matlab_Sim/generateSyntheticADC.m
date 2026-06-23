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
    hannR = hanning(nSamp);
    hannD = hanning(nRamp);

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
        % White noise is uncorrelated from ramp to ramp, so DRHE (which predicts
        % each ramp from the previous one) cannot compress it: at a given noise
        % floor the compression ratio is pinned near 1. REAL radar data sits on a
        % floor that is largely *correlated* across ramps (slow-moving clutter,
        % phase noise, etc.), which is exactly why DRHE achieves CR ~3 on it.
        % We optionally model this with a first-order (AR(1)) slow-time
        % correlation of coefficient noiseCorr in [0,1): the floor keeps the same
        % power (so the noise floor in dBFS is unchanged) but consecutive ramps
        % become similar, so the ramp-to-ramp differences DRHE encodes shrink and
        % the compression ratio climbs. noiseCorr = 0 reproduces the clean,
        % incompressible white-noise floor.
        if isfield(config, 'noiseCorr') && config.noiseCorr > 0
            rho = config.noiseCorr;
            innov = noiseSigmaADC * randn(nSamp, nRamp);
            noise = zeros(nSamp, nRamp);
            noise(:, 1) = innov(:, 1);
            s = sqrt(1 - rho^2);
            for mm = 2:nRamp
                noise(:, mm) = rho * noise(:, mm-1) + s * innov(:, mm);
            end
        else
            noise = noiseSigmaADC * randn(nSamp, nRamp);
        end
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
