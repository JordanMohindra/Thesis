%% Radar Data Compression Simulation - CLEAN (idealised) scene
%  Replicates Kiem's workflow (Section 3.2, Figure 3.1) on *idealised
%  synthetic data*: a dense field of point targets on a white-noise floor.
%
%  PURPOSE
%  This is the honest "clean simulated data" case. It reproduces Kiem's
%  detection-side numbers very closely:
%      - noise floor (NF)  ~ -70.7 dBFS
%      - SNR               ~ 22-24 dB
%      - FX16/DRHE lose a tiny fraction of targets that FP16 keeps
%        (small FN%, small FP%)
%  ...but the DRHE compression ratio is only ~1.1.
%
%  WHY CR STAYS ~1.1 HERE
%  DRHE compresses by predicting each ramp from the previous one and storing
%  the (small) difference. White receiver noise is completely uncorrelated
%  from ramp to ramp, so the differences are as large as the noise itself:
%  at a -70.7 dBFS floor each difference needs ~15 bits, pinning CR near 1.
%  A high noise floor (good, realistic NF) and a high CR are therefore
%  mutually exclusive for purely white-noise data - see main_simulation_clutter.m
%  for the realistic, correlated-clutter counterpart that breaks this tie.

clear; clc; close all;

%% ---------------- Build scene + pipeline configuration ----
% Scene details live in buildSceneConfig.m (shared with the clutter scene
% and the comparison driver main_simulation.m).
config = buildSceneConfig('clean');

%% ---------------- Run the four-path workflow -------------
fprintf('================================================================\n');
fprintf('  RADAR DATA COMPRESSION SIMULATION - CLEAN (idealised) scene\n');
fprintf('================================================================\n');

fullScaleRefPower = computeFullScaleRefPower(config);
rng(42);   % fix the noise / target-phase realisation for reproducibility
results = runCompressionSim(config, fullScaleRefPower, 'clean (white-noise floor)');

%% ---------------- Kiem reference + interpretation --------
printKiemReference();
fprintf('\n  Interpretation (CLEAN scene):\n');
fprintf('    * NF, SNR, FN%% and FP%% closely match Kiem''s Table 3.5.\n');
fprintf('    * DRHE CR ~ %.2f only: white noise is incompressible, so at a\n', results.metricsDRHE.CR);
fprintf('      -70.7 dBFS floor the ramp-to-ramp differences cost ~15 bits each.\n');
fprintf('    * To also reach Kiem''s CR = 3.25 the data must be dominated by\n');
fprintf('      *correlated* returns -> see main_simulation_clutter.m\n');

%% ---------------- Plots ----------------------------------
plotProcessingStages(results.rangeFFTData, results.dopplerFFTRef, results.rdMapRef, config);
plotCompressionComparison(results.rdMapFP16, results.rdMapFX16, config, fullScaleRefPower);
fprintf('\n  Plots generated. CLEAN simulation complete.\n');
