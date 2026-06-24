function config = buildSceneConfig(sceneType, preset)
% BUILDSCENECONFIG Builds the configuration for a CLEAN, CLUTTERED or KIEM scene.
%
%   config = buildSceneConfig(sceneType)
%   config = buildSceneConfig(sceneType, preset)   % only the 'kiem' scene uses preset
%
%   sceneType : 'clean'   - idealised: dense point targets on a white-noise
%                           floor. Matches Kiem's NF/SNR/FN/FP (Table 3.5) but
%                           DRHE CR ~ 1.1 (white noise is incompressible).
%               'clutter' - strong zero-Doppler clutter plus moving targets on
%                           a low thermal floor. CR ~ 2.6 but NF/SNR depart
%                           from Kiem.
%               'kiem'    - "Kiem-realistic" unified scene: matches Kiem's
%                           Table 3.1 pipeline (512 samples x 512 ramps x 4 RX,
%                           14-bit ADC). See PRESETS below for the four
%                           parameter dial-ins along the NF <-> CR trade-off.
%
%   preset   : (used only when sceneType=='kiem'; default 'match-fnfp')
%       'match-nf'    AWGN -70.5, ENOB 11. NF/SNR/refDet match Kiem;
%                     FN/FP = 0; CR ~ 1.11. Lightest quantisation.
%       'match-fnfp'  AWGN -70.5, ENOB  9. NF still at Kiem AND ~0.6%
%                     FN/FP (one detection flipped) -> reproduces Kiem's
%                     FX-loses-targets signature. CR ~ 1.10. [DEFAULT]
%       'match-cr'    AWGN -85,   ENOB 12. Drops NF by ~14 dB to free DRHE
%                     residuals -> CR ~ 1.5; FN/FP = 0.
%       'match-cr-aggressive'  AWGN -95, ENOB 13. NF ~ -95 dBFS; CR ~ 2.0;
%                     FX16 stable, FN/FP = 0. Highest CR achievable on
%                     synthetic data while keeping FX from collapsing.

    if nargin < 2
        preset = 'match-fnfp';   % default kiem preset
    end

    config.numRamps      = 512;
    config.numRxChannels = 4;
    config.bitWidth      = 14;
    config.fullScaleBackoff = 0.95;   % anti-clipping guard (statistical peak)

    if strcmpi(sceneType, 'kiem')
        config.numSamples = 512;      % Kiem Table 3.1 real-data config
    else
        config.numSamples = 1024;
    end

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

        case 'kiem'
            % ---- "Kiem-realistic" unified scene (target = Table 3.5) ----
            % This scene tries to reproduce ALL FIVE numbers of Kiem's Table 3.5
            % from synthetic data alone. Final tuned parameters were chosen
            % from a directed parameter sweep (see kiem_sweep1..6.txt history).
            %
            % MECHANISM
            %   Real terrestrial data hits NF -70.7 dBFS *and* DRHE CR 3.25
            %   simultaneously because most floor energy is coherent clutter
            %   that DRHE's IIR predictor can track. We mimic that with three
            %   coherent population tiers, but as the sweeps show, *broadband*
            %   AWGN that survives the metric mask is what sets the floor; it
            %   is also what caps the CR. The synthetic CR ceiling at
            %   NF = -70.7 dBFS is ~ 1.1 (the rest of Kiem's CR comes from
            %   compressible energy in the floor that white noise cannot
            %   reproduce).
            %
            % SCENE
            %   1) ~170 coherent low-Doppler scatterers populate the
            %      detection list (-> refDet ~ Kiem's ~170).
            %   2) 8 mid-Doppler "main" targets at moderate amplitude.
            %   3) 6 weak targets sitting near the detection threshold for the
            %      FX-vs-FP quantisation demo (.weakTargetIdx).
            %   AWGN at -70.5 dBFS sets the measured noise floor.
            %
            % RESULT (Kiem in brackets)
            %   refDet ~ 160 (170), NF ~ -71.0 (-70.7), SNR ~ 23.8 (22.3),
            %   FN/FP small (0.59 / 1.18), DRHE CR ~ 1.1 (3.25 - the gap).

            rng(11);

            % --- (1) Coherent low-Doppler clutter field (sets refDet/NF) ---
            nClutter = 170;
            clutterRangeBins   = randi([5, 250], 1, nClutter);
            clutterDopplerBins = randi([2,  30], 1, nClutter);
            clutterAmplitudes  = 3.5e-3 * 10.^(0.18 * randn(1, nClutter));
            clutterAmplitudes  = max(clutterAmplitudes, 1.0e-3);
            clutterAmplitudes  = min(clutterAmplitudes, 1.2e-2);

            % --- (2) Main moving targets (modest, so SNR ~ Kiem's 22 dB) ---
            mainScale       = 0.30;
            mainRangeBins   = [ 40,  80, 120, 160, 200,  50, 100, 220];
            mainDopplerBins = [ 80, 130,  60, 180, 230, 350, 410, 290];
            mainAmplitudes  = mainScale * 0.020 * ...
                              [1.20, 1.10, 1.00, 1.20, 0.90, 1.00, 1.10, 0.95];

            % --- (3) Weak-target tier (FX vs FP demo) ---
            nWeak           = 6;
            weakRangeBins   = [ 30,  70, 110, 150, 190, 230];
            weakDopplerBins = [100, 150, 200, 250, 300, 350];
            weakAmplitudes  = linspace(1.0e-3, 2.0e-3, nWeak);

            config.targetRangeBins   = [clutterRangeBins,   mainRangeBins,   weakRangeBins];
            config.targetDopplerBins = [clutterDopplerBins, mainDopplerBins, weakDopplerBins];
            config.targetAmplitudes  = [clutterAmplitudes,  mainAmplitudes,  weakAmplitudes];
            config.numTargets        = numel(config.targetAmplitudes);
            config.weakTargetIdx     = (config.numTargets - nWeak + 1):config.numTargets;

            % --- Preset dial-in along the NF <-> CR trade-off -----------
            % Both noiseLevelDB and fx16EffectiveBits change between presets;
            % everything else stays fixed so the comparison is apples-to-apples.
            switch lower(preset)
                case 'match-nf'
                    config.noiseLevelDB      = -70.5;   % directly sets NF
                    config.fx16EffectiveBits = 11;       % FN/FP = 0
                case 'match-fnfp'
                    config.noiseLevelDB      = -70.5;   % NF still at Kiem
                    config.fx16EffectiveBits = 9;        % flips ~1 of 170 -> FN/FP > 0
                case 'match-cr'
                    config.noiseLevelDB      = -85;     % lower AWGN -> bigger CR
                    config.fx16EffectiveBits = 12;       % higher ENOB so FX stays stable
                case 'match-cr-aggressive'
                    config.noiseLevelDB      = -95;     % near clutter-scene regime
                    config.fx16EffectiveBits = 13;       % required to avoid FX collapse
                otherwise
                    error('buildSceneConfig:unknownPreset', ...
                          'Unknown kiem preset "%s". Use match-nf | match-fnfp | match-cr | match-cr-aggressive.', preset);
            end
            config.kiemPreset = lower(preset);
            % No Doppler guard: the low-Doppler clutter scatterers ARE the
            % bulk of the detection list (~ Kiem's ~170).

        otherwise
            error('buildSceneConfig:badType', ...
                'sceneType must be ''clean'', ''clutter'' or ''kiem'' (got ''%s'').', sceneType);
    end
end
