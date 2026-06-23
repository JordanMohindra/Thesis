%% Radar Data Compression Simulation - CLEAN vs CLUTTERED comparison driver
%  Runs both scenes through Kiem's four-path workflow (Reference / FP16 /
%  FX16 / DRHE, Figure 3.1) and prints them side by side against Kiem's
%  Table 3.5 real-data reference.
%
%  For the detailed, plotted single-scene runs use:
%      main_simulation_clean.m     - idealised white-noise data
%      main_simulation_clutter.m   - realistic correlated-clutter data
%
%  THE BIG PICTURE
%  Kiem's real data hits BOTH a high noise floor (-70.7 dBFS) AND a high
%  compression ratio (3.25). For idealised simulated data these two cannot be
%  achieved at once, because DRHE's compression ratio is governed by the noise
%  level in code units (a high floor => large ramp-to-ramp differences => CR
%  near 1). The two scenes therefore bracket Kiem's result:
%      CLEAN    -> matches NF / SNR / FN% / FP%   (CR ~ 1.1)
%      CLUTTER  -> matches the compression ratio  (CR ~ 2.5-2.7; NF/SNR differ)
%  Real data escapes the trade-off because its -70.7 dBFS "floor" is itself
%  largely correlated clutter, which DRHE compresses.

clear; clc; close all;

fprintf('================================================================\n');
fprintf('  RADAR DATA COMPRESSION SIMULATION\n');
fprintf('  CLEAN (idealised) vs CLUTTERED (realistic) - comparison\n');
fprintf('================================================================\n');

%% ---- Run both scenes ----
cfgClean = buildSceneConfig('clean');
PrefClean = computeFullScaleRefPower(cfgClean);
rng(42);
resClean = runCompressionSim(cfgClean, PrefClean, 'clean (white-noise floor)');

cfgClutter = buildSceneConfig('clutter');
PrefClutter = computeFullScaleRefPower(cfgClutter);
rng(42);
resClutter = runCompressionSim(cfgClutter, PrefClutter, 'cluttered (correlated clutter)');

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

printKiemReference();

fprintf('\n  Take-away:\n');
fprintf('    * CLEAN   reproduces Kiem''s NF / SNR / FN%% / FP%% but CR ~ %.2f.\n', resClean.metricsDRHE.CR);
fprintf('    * CLUTTER reproduces the high compression ratio (CR ~ %.2f) because\n', resClutter.metricsDRHE.CR);
fprintf('      correlated clutter is nearly free for DRHE to store; its NF/SNR\n');
fprintf('      differ because a high CR forces a low noise floor for synthetic data.\n');
fprintf('\n================================================================\n');
fprintf('  COMPARISON COMPLETE\n');
fprintf('================================================================\n');
