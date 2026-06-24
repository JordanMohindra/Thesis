%% Radar Data Compression Simulation - CLEAN vs CLUTTER vs KIEM-REALISTIC
%  Runs all three scenes through Kiem's four-path workflow (Reference / FP16 /
%  FX16 / DRHE, Figure 3.1) and prints them side by side against Kiem's
%  Table 3.5 real-data reference.
%
%  For the detailed, plotted single-scene runs use:
%      main_simulation_clean.m   - idealised white-noise data (FX-vs-FP demo)
%      main_simulation_clutter.m - correlated-clutter data (CR demo)
%      main_simulation_kiem.m    - Kiem-realistic unified scene (Table 3.1 dims)
%
%  THE BIG PICTURE
%  Kiem's real data hits BOTH a high noise floor (-70.7 dBFS) AND a high
%  compression ratio (3.25). For idealised SYNTHETIC data these two cannot
%  be achieved at once, because DRHE's CR is governed by the AWGN sigma in
%  code units (a high floor => large ramp-to-ramp residuals => CR near 1).
%  The three scenes therefore bracket Kiem's result:
%      CLEAN    -> matches NF / SNR / FN% / FP%        (CR ~ 1.1)
%      CLUTTER  -> matches the compression ratio       (CR ~ 2.5; NF/SNR differ)
%      KIEM     -> closest single-scene match overall  (CR caps at AWGN bound)
%  Real data escapes the trade-off because its -70.7 dBFS "floor" is itself
%  largely correlated clutter, which DRHE compresses.

clear; clc; close all;

fprintf('================================================================\n');
fprintf('  RADAR DATA COMPRESSION SIMULATION\n');
fprintf('  CLEAN vs CLUTTERED vs KIEM-REALISTIC - 3-way comparison\n');
fprintf('================================================================\n');

%% ---- Run all three scenes ----
cfgClean = buildSceneConfig('clean');
PrefClean = computeFullScaleRefPower(cfgClean);
rng(42);
resClean = runCompressionSim(cfgClean, PrefClean, 'clean (white-noise floor)');

cfgClutter = buildSceneConfig('clutter');
PrefClutter = computeFullScaleRefPower(cfgClutter);
rng(42);
resClutter = runCompressionSim(cfgClutter, PrefClutter, 'cluttered (correlated clutter)');

% Which Kiem preset to compare against the clean/clutter scenes.
% Options: 'match-nf' | 'match-fnfp' | 'match-cr' | 'match-cr-aggressive'
KIEM_PRESET = 'match-fnfp';
cfgKiem = buildSceneConfig('kiem', KIEM_PRESET);
PrefKiem = computeFullScaleRefPower(cfgKiem);
rng(42);
resKiem = runCompressionSim(cfgKiem, PrefKiem, sprintf('kiem-realistic (%s)', KIEM_PRESET));

%% ---- Side-by-side summary ----
fprintf('\n================================================================\n');
fprintf('  SIDE-BY-SIDE SUMMARY (Algorithm | CR | FN%% | FP%% | NF dBFS | SNR dB)\n');
fprintf('================================================================\n');

printRow = @(name, m) fprintf('  %-6s %6.2f %7.2f %7.2f %11.3f %9.3f\n', ...
    name, m.CR, m.FN_pct, m.FP_pct, m.NF_dBFS, m.SNR_dB);

fprintf('\n  CLEAN (idealised white-noise data):\n');
printRow('FP16', resClean.metricsFP16);
printRow('FX16', resClean.metricsFX16);
printRow('DRHE', resClean.metricsDRHE);

fprintf('\n  CLUTTERED (realistic correlated-clutter data):\n');
printRow('FP16', resClutter.metricsFP16);
printRow('FX16', resClutter.metricsFX16);
printRow('DRHE', resClutter.metricsDRHE);

fprintf('\n  KIEM-REALISTIC (preset %s):\n', KIEM_PRESET);
printRow('FP16', resKiem.metricsFP16);
printRow('FX16', resKiem.metricsFX16);
printRow('DRHE', resKiem.metricsDRHE);

printKiemReference();

fprintf('\n  Take-away:\n');
fprintf('    * CLEAN   reproduces Kiem''s NF / SNR / FN%% / FP%% but CR ~ %.2f.\n', resClean.metricsDRHE.CR);
fprintf('    * CLUTTER reproduces the high compression ratio (CR ~ %.2f) because\n', resClutter.metricsDRHE.CR);
fprintf('      correlated clutter is nearly free for DRHE to store; its NF/SNR\n');
fprintf('      differ because a high CR forces a low noise floor for synthetic data.\n');
fprintf('    * KIEM-REALISTIC gets closest to Kiem in a SINGLE scene (NF %.2f,\n', resKiem.metricsDRHE.NF_dBFS);
fprintf('      SNR %.2f, refDet %d), but CR stays at ~ %.2f - the synthetic AWGN\n', ...
    resKiem.metricsDRHE.SNR_dB, resKiem.refDetections, resKiem.metricsDRHE.CR);
fprintf('      ceiling. Real data escapes this only because its floor IS clutter.\n');
fprintf('\n================================================================\n');
fprintf('  COMPARISON COMPLETE\n');
fprintf('================================================================\n');
