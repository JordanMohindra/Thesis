%% Radar Data Compression Simulation - "KIEM-REALISTIC" unified scene
%  Single synthetic scene that tries to reproduce ALL FIVE numbers of Kiem's
%  Table 3.5 (FP16 / FX16 / DRHE on real radar data id=1) at once. Uses
%  Kiem's Table 3.1 real-data pipeline exactly: 512 samples x 512 ramps x 4 RX,
%  14-bit ADC.
%
%  PURPOSE
%  Kiem's real-data result (Table 3.5) hits both a high noise floor
%  (-70.7 dBFS) AND a high compression ratio (3.25). The CLEAN scene
%  (main_simulation_clean.m) reproduces NF / SNR / FN / FP but only CR ~ 1.1;
%  the CLUTTER scene (main_simulation_clutter.m) reproduces CR ~ 2.6 but at
%  NF ~ -100 dBFS. This script is the honest attempt to do both in one scene.
%
%  SWAPPING BETWEEN VARIANTS
%  Two switches at the top of this script:
%
%       PRESET      = 'match-fnfp';   % see buildSceneConfig.m header
%       RUN_SWEEP   = false;          % true -> run all four presets side-by-side
%
%  PRESETS (only relevant when RUN_SWEEP = false):
%     'match-nf'             NF/SNR/refDet best match; FN = FP = 0; CR ~ 1.1
%     'match-fnfp'  [DEFAULT] NF still at Kiem AND ~0.6% FN matching Kiem
%                            (ENOB = 9); CR ~ 1.1
%     'match-cr'             AWGN -85 dBFS, ENOB 12; CR ~ 1.5; NF lower
%     'match-cr-aggressive'  AWGN -95 dBFS, ENOB 13; CR ~ 2.0; NF much lower
%     'noise-mixed-mild'     Same scene as match-nf but uses MIXED noise
%                            (70% white + 30% AR1 rho=0.99). Tests whether
%                            non-AWGN correlated noise can lift CR at iso-NF.
%                            Result: CR drops to ~1.09 (correlated noise
%                            does NOT break the NF<->CR trade-off).
%     'noise-mixed-strong'   50/50 mix with rho=0.999. Counter-example for
%                            the same hypothesis - confirms only coherent
%                            clutter (not correlated noise) can lift CR.
%
%  PIPELINE BACKGROUND
%   * 170 coherent low-Doppler scatterers (Doppler bins 2-30) populate the
%     detection list (~ Kiem's ~170).
%   * 8 mid-Doppler "main" targets at moderate amplitude (set the SNR).
%   * 6 weak targets near the detection threshold for the FX-vs-FP demo
%     (.weakTargetIdx). Lower ENOB lets FX16 lose them or invent new ones.
%   * AWGN level set per preset.
%
%  WHY CR CAPS BELOW KIEM
%  The measured NF is the mean-in-dB of all non-peak RD cells, which is
%  dominated by AWGN. The same AWGN sets the FX16 code std, which sets the
%  DRHE residual size, which caps CR. So NF and CR trade off rigidly on
%  synthetic AWGN data. Real data escapes only because its "noise floor" is
%  itself largely coherent clutter that DRHE can predict.

clear; clc; close all;

%% ============ CONFIGURATION SWITCHES (edit these) =================
PRESET    = 'match-fnfp';   % 'match-nf' | 'match-fnfp' | 'match-cr' | 'match-cr-aggressive'
RUN_SWEEP = false;          % set true to run all four presets side-by-side
% ===================================================================

if RUN_SWEEP
    runAllPresets();
else
    runSinglePreset(PRESET);
end

%% ============= local: single preset ==============================
function runSinglePreset(presetName)
    config = buildSceneConfig('kiem', presetName);

    fprintf('================================================================\n');
    fprintf('  RADAR DATA COMPRESSION SIMULATION - KIEM-REALISTIC unified scene\n');
    fprintf('  Preset: ''%s''\n', presetName);
    fprintf('  Pipeline: %d x %d x %d, %d-bit, AWGN = %.1f dBFS, FX ENOB = %d\n', ...
        config.numSamples, config.numRamps, config.numRxChannels, ...
        config.bitWidth, config.noiseLevelDB, config.fx16EffectiveBits);
    fprintf('================================================================\n');

    Pref = computeFullScaleRefPower(config);
    rng(42);
    results = runCompressionSim(config, Pref, sprintf('kiem-%s', presetName));

    printKiemReference();
    fprintf('\n  Interpretation (preset %s):\n', presetName);
    fprintf('    refDet=%d, NF=%.2f, SNR=%.2f, CR=%.2f, FN=%.2f%%, FP=%.2f%%.\n', ...
        results.refDetections, results.metricsDRHE.NF_dBFS, ...
        results.metricsDRHE.SNR_dB, results.metricsDRHE.CR, ...
        results.metricsFX16.FN_pct, results.metricsFX16.FP_pct);

    plotProcessingStages(results.rangeFFTData, results.dopplerFFTRef, results.rdMapRef, config);
    plotCompressionComparison(results.rdMapFP16, results.rdMapFX16, config, Pref);
    fprintf('\n  Plots generated. KIEM-REALISTIC (%s) complete.\n', presetName);
end

%% ============= local: sweep all presets =========================
function runAllPresets()
    presets = {'match-nf', 'match-fnfp', ...
               'noise-mixed-mild', 'noise-mixed-strong', ...
               'match-cr', 'match-cr-aggressive'};

    fprintf('================================================================\n');
    fprintf('  KIEM-REALISTIC: SWEEP OVER ALL PRESETS\n');
    fprintf('================================================================\n');

    rows = struct([]);
    for k = 1:numel(presets)
        config = buildSceneConfig('kiem', presets{k});
        Pref = computeFullScaleRefPower(config);
        rng(42);
        r = runCompressionSim(config, Pref, sprintf('kiem-%s', presets{k}));
        rows(k).name = presets{k};
        rows(k).enob = config.fx16EffectiveBits;
        rows(k).awgn = config.noiseLevelDB;
        if isfield(config, 'noiseType')
            rows(k).ntype = config.noiseType;
        else
            rows(k).ntype = 'white';
        end
        rows(k).res  = r;
    end

    fprintf('\n================================================================\n');
    fprintf('  PRESET COMPARISON (DRHE metrics; FX16 FN%%/FP%% in last col)\n');
    fprintf('================================================================\n');
    fprintf('  %-22s %-7s %-6s %-8s %8s %8s %8s %8s %-14s\n', ...
        'preset', 'noise', 'ENOB', 'AWGN', 'refDet', 'NF', 'SNR', 'CR', 'FN%/FP% (FX16)');
    for k = 1:numel(rows)
        r = rows(k).res;
        fprintf('  %-22s %-7s %-6d %-8.1f %8d %8.2f %8.2f %8.2f   %5.2f / %5.2f\n', ...
            rows(k).name, rows(k).ntype, rows(k).enob, rows(k).awgn, ...
            r.refDetections, r.metricsDRHE.NF_dBFS, r.metricsDRHE.SNR_dB, ...
            r.metricsDRHE.CR, r.metricsFX16.FN_pct, r.metricsFX16.FP_pct);
    end

    printKiemReference();
    fprintf('\n  Read the table top-to-bottom as the NF<->CR trade-off curve:\n');
    fprintf('   * match-nf / match-fnfp / noise-mixed-* all hold NF at Kiem;\n');
    fprintf('     CR is pinned near 1.1 (independent of noise model).\n');
    fprintf('   * match-cr / match-cr-aggressive trade NF away for higher CR.\n');
    fprintf('   * the noise-mixed-* rows confirm: replacing AWGN with CORRELATED\n');
    fprintf('     noise does NOT lift CR at iso-NF - the trade-off is intrinsic\n');
    fprintf('     to the metric, not to the noise distribution. Only coherent\n');
    fprintf('     CLUTTER (extra scatterers) can lift CR while holding NF.\n');
end
