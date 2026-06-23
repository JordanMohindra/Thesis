%% Radar Data Compression Simulation - CLUTTERED (realistic) scene
%  Replicates Kiem's workflow (Section 3.2, Figure 3.1) on *realistic*
%  clutter-dominated data: a dense field of strong, stationary
%  (zero-Doppler) clutter returns plus moving targets, on a low thermal-noise
%  floor.
%
%  PURPOSE
%  This is the realistic counterpart to main_simulation_clean.m. Real radar
%  data is dominated by correlated clutter (ground, buildings, etc.) that is
%  nearly identical from ramp to ramp. DRHE predicts those returns almost
%  perfectly, so they cost very few bits and the compression ratio climbs far
%  above the clean white-noise case:
%      - DRHE CR ~ 2.5-2.7  (vs ~1.1 for the clean scene; Kiem's real data: 3.25)
%
%  HOW IT WORKS / KEY DIFFERENCES vs CLEAN
%   1. config.targetDopplerBins == 1 entries are STATIONARY CLUTTER lines:
%      constant across ramps -> perfectly predictable -> highly compressible.
%   2. config.dopplerGuardBins rejects the zero-Doppler column from detection
%      (standard stationary-clutter rejection) so the clutter is not reported
%      as thousands of false targets.
%   3. The thermal noise floor is set low. DRHE compression is limited by the
%      *incompressible* white noise: a low floor (small FX16 codes) is what
%      lets the ramp-to-ramp differences shrink to a few bits and the CR rise.
%
%  TRADE-OFF (why this scene's NF/SNR differ from Kiem's -70.7 / 22 dB)
%  A high noise floor (-70.7 dBFS) and a high CR (3.25) cannot coexist for
%  idealised simulated data: CR is governed by the noise level in code units,
%  so reaching a high CR forces a lower NF (and hence a higher SNR) here. Real
%  data escapes this because its -70.7 dBFS "floor" is itself largely
%  correlated clutter. The clean and cluttered scripts together bracket Kiem:
%  CLEAN matches NF/SNR/FN/FP, CLUTTER matches the compression ratio.

clear; clc; close all;

%% ---------------- Build scene + pipeline configuration ----
% Scene details live in buildSceneConfig.m (shared with the clean scene and
% the comparison driver main_simulation.m).
config = buildSceneConfig('clutter');

%% ---------------- Run the four-path workflow -------------
fprintf('================================================================\n');
fprintf('  RADAR DATA COMPRESSION SIMULATION - CLUTTERED (realistic) scene\n');
fprintf('================================================================\n');

fullScaleRefPower = computeFullScaleRefPower(config);
rng(42);   % fix the noise / target-phase realisation for reproducibility
results = runCompressionSim(config, fullScaleRefPower, 'cluttered (correlated clutter)');

%% ---------------- Kiem reference + interpretation --------
printKiemReference();
fprintf('\n  Interpretation (CLUTTERED scene):\n');
fprintf('    * DRHE CR ~ %.2f - the stationary clutter is correlated ramp-to-ramp,\n', results.metricsDRHE.CR);
fprintf('      so DRHE predicts it almost for free. This is the mechanism behind\n');
fprintf('      Kiem''s CR = 3.25 on real data (vs ~1.1 for the clean scene).\n');
fprintf('    * NF ~ %.1f dBFS / SNR ~ %.1f dB: the floor is lower (and SNR higher)\n', ...
    results.metricsDRHE.NF_dBFS, results.metricsDRHE.SNR_dB);
fprintf('      than Kiem because a high CR forces a low noise floor for synthetic data.\n');

%% ---------------- Plots ----------------------------------
plotProcessingStages(results.rangeFFTData, results.dopplerFFTRef, results.rdMapRef, config);
plotCompressionComparison(results.rdMapFP16, results.rdMapFX16, config, fullScaleRefPower);
fprintf('\n  Plots generated. CLUTTERED simulation complete.\n');
