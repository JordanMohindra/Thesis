function config = buildSceneConfig(sceneType)
% BUILDSCENECONFIG Builds the configuration for a CLEAN or CLUTTERED scene.
%   Both scenes share the same pipeline (1024 x 512 x 4, 14-bit ADC) and are
%   used by main_simulation_clean.m, main_simulation_clutter.m and the
%   side-by-side driver main_simulation.m.
%
%   sceneType : 'clean'   - idealised: dense point targets on a white-noise
%                           floor. Matches Kiem's NF/SNR/FN/FP (Table 3.5) but
%                           DRHE CR ~ 1.1 (white noise is incompressible).
%               'clutter' - realistic: strong stationary (correlated) clutter
%                           plus moving targets on a low thermal floor. DRHE
%                           CR ~ 2.5-2.7 because the clutter is predictable,
%                           but NF/SNR depart from Kiem (a high CR forces a low
%                           noise floor for synthetic data).
%
%   The two scenes together bracket Kiem's real-data result: CLEAN reproduces
%   the detection-side metrics, CLUTTER reproduces the compression ratio.

    config.numSamples    = 1024;
    config.numRamps      = 512;
    config.numRxChannels = 4;
    config.bitWidth      = 14;
    config.fullScaleBackoff = 0.95;   % anti-clipping guard (statistical peak)

    switch lower(sceneType)
        case 'clean'
            % ---- Dense moving-target field, white-noise floor ----
            % ~210 targets so FN/FP have fine granularity (Kiem: 0.59 / 1.18%
            % = 1-2 of ~170 detections). Doppler bins clear of DC so all are
            % detectable. Amplitudes centred to give SNR ~ 22-24 dB.
            rng(7);
            N = 204;
            mainRangeBins   = randi([8, 505], 1, N);
            mainDopplerBins = randi([40, 470], 1, N);
            amp = 0.70 * 10.^(-2.5 + 0.34 * randn(1, N));
            amp = min(amp, 9e-3);
            amp = max(amp, 1.4e-3);   % robust main field (well above threshold)

            % ---- Weak-target tier (the FX-vs-FP quantisation demo) ----
            % A handful of faint targets sitting just above the detection
            % threshold. FP16 (floating-point) preserves them; the FX16
            % (fixed-point) path quantises the range-FFT to a uniform grid, which
            % adds quantisation noise around these faint returns - the difference
            % panel of plotCompressionComparison makes that error visible, and the
            % marginal ones flip detection (the small FN%/FP% Kiem also reports).
            nWeak           = 6;
            weakRangeBins   = [60 150 230 300 370 450];
            weakDopplerBins = [90 160 220 280 340 410];
            weakAmp         = linspace(1.3e-3, 1.7e-3, nWeak);

            config.targetRangeBins   = [mainRangeBins,   weakRangeBins];
            config.targetDopplerBins = [mainDopplerBins, weakDopplerBins];
            config.targetAmplitudes  = [amp,             weakAmp];
            config.numTargets        = N + nWeak;
            config.weakTargetIdx     = (N + 1):(N + nWeak);  % circled in the plot

            config.noiseLevelDB      = -70.5;  % -> NF ~ -70.7 dBFS
            config.fx16EffectiveBits = 11;     % FX16 effective bits (< 16) -> small loss
            % no clutter, no Doppler guard

        case 'clutter'
            % ---- Stationary clutter + moving targets, low noise floor ----
            % (1) 90 strong zero-Doppler (bin 1) clutter lines across range:
            %     constant across ramps -> correlated -> DRHE-compressible.
            clutterRangeBins   = round(linspace(10, 502, 90));
            clutterDopplerBins = ones(1, 90);
            clutterAmplitudes  = 0.025 * ones(1, 90);

            % (2) Moving targets above the floor, clear of the clutter guard band.
            rng(7);
            NR = 45;
            movingRangeBins   = randi([8, 505], 1, NR);
            movingDopplerBins = randi([45, 468], 1, NR);
            movingAmp = 10.^(-2.1 + 0.22 * randn(1, NR));
            movingAmp = min(movingAmp, 2.2e-2);
            movingAmp = max(movingAmp, 4.0e-3);

            % (3) Weak-target tier near the low thermal floor (the FX-vs-FP demo).
            %     This is a low-noise, high-dynamic-range scene, so fixed-point
            %     QUANTISATION is the dominant error (not thermal noise). FP16
            %     preserves these faint targets with its floating exponent, while
            %     FX16's uniform grid buries the faintest in quantisation noise -
            %     the clearest fixed-vs-float demonstration.
            nWeak           = 6;
            weakRangeBins   = [60 150 230 300 370 450];
            weakDopplerBins = [90 160 220 280 340 410];
            weakAmp         = linspace(8e-5, 3e-4, nWeak);

            config.targetRangeBins   = [clutterRangeBins,   movingRangeBins, weakRangeBins];
            config.targetDopplerBins = [clutterDopplerBins, movingDopplerBins, weakDopplerBins];
            config.targetAmplitudes  = [clutterAmplitudes,  movingAmp,        weakAmp];
            config.numTargets        = numel(config.targetAmplitudes);
            config.weakTargetIdx     = (config.numTargets - nWeak + 1):config.numTargets;

            config.noiseLevelDB      = -104;   % low floor -> small FX16 codes -> high CR
            config.fx16EffectiveBits = 13;     % FX16 effective bits (< 16)
            config.dopplerGuardBins  = 35;     % stationary-clutter rejection in detection

        otherwise
            error('buildSceneConfig:badType', ...
                'sceneType must be ''clean'' or ''clutter'' (got ''%s'').', sceneType);
    end
end
