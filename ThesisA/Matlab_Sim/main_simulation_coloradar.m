%% Radar Data Compression Simulation - COLORADAR CASCADE (single frame)
%  Loads ONE ColoRadar cascade frame_<N>.bin and runs it through Kiem's
%  five-path compression workflow (Reference / FP16 / DRHEfp16 / FX16 / DRHE,
%  Figure 3.1). Mirrors main_simulation_real.m but for the ColoRadar dataset
%  (TI MMWCAS-RF-EVM cascade: 256 samples x 16 chirps x 16 RX x 12 TX,
%  complex int16, ~3.1 MB per frame).
%
%  WHAT THIS SHOWS
%   * Real radar data has correlated clutter and oscillator structure across
%     ramps, which is exactly what DRHE compresses. Expect CR markedly > 1
%     (unlike the synthetic AWGN limit of ~ 1.1).
%   * FP16 vs FX16 quantisation comparison on a real range-Doppler map.
%   * Detection metrics on the cascade NCI image: how many peaks survive
%     each compression step.
%
%  HOW IT WORKS
%   loadColoRadarFrame.m reads frame_<N>.bin, parses the 256 x 16 x 16 x 12
%   complex int16 layout (per Kramer et al. 2021 arXiv:2103.04510), flattens
%   the 12 TX into the ramp axis in TDM time order, and returns a cube of
%   shape [256 x 192 x 16] that runCompressionSim consumes directly via its
%   4th argument. No code in the compression workflow needs changes - the
%   pipeline already supports complex input via config.complexInput.

clear; clc; close all;

%% ============ CONFIGURATION (edit these) ==========================
FRAME_INDEX = 6;              % which frame_<N>.bin to load
TX_SELECT   = 1:12;           % which TX antennas to use (1:12 = all)
FX16_ENOB   = 16;             % effective FX16 bits (16 = lossless container)
REMOVE_DC   = true;           % subtract per-ramp mean per channel
RANGE_MAX_PLOT = 25;          % [m] range axis cap for plots
VEL_MAX_PLOT   = [];          % [m/s] velocity axis cap ([] = radar Nyquist)
% ===================================================================

%% --- locate the frame ---------------------------------------------
candidatePaths = { ...
    fullfile(fileparts(mfilename('fullpath')), '..', '..', '..', 'Jordan''s Thesis', 'cascade', 'adc_samples', 'data'), ...
    fullfile(fileparts(mfilename('fullpath')), '..', '..', 'Jordan''s Thesis', 'cascade', 'adc_samples', 'data'), ...
    'C:\Users\mohin\Downloads\12_21_2020_ec_hallways_run4\12_21_2020_ec_hallways_run4\cascade\adc_samples\data' ...
};

binFile = '';
for i = 1:length(candidatePaths)
    testFile = fullfile(candidatePaths{i}, sprintf('frame_%d.bin', FRAME_INDEX));
    if exist(testFile, 'file') == 2
        binFile = testFile;
        dataDir = candidatePaths{i};
        break;
    end
end

if isempty(binFile)
    error('main_simulation_coloradar:notFound', ...
          'Frame file frame_%d.bin not found in candidate directories.', FRAME_INDEX);
end

fprintf('================================================================\n');
fprintf('  RADAR DATA COMPRESSION SIMULATION - COLORADAR CASCADE\n');
fprintf('  frame %d, TX = %s\n', FRAME_INDEX, mat2str(TX_SELECT));
fprintf('================================================================\n');

%% --- load the frame -----------------------------------------------
opts = struct( ...
    'txSelect',          TX_SELECT, ...
    'removeDC',          REMOVE_DC, ...
    'fx16EffectiveBits', FX16_ENOB, ...
    'rangeMaxPlot',      RANGE_MAX_PLOT, ...
    'velMaxPlot',        VEL_MAX_PLOT);
[cube, config, axesInfo] = loadColoRadarFrame(binFile, opts);

%% --- run the compression workflow -----------------------------------
fullScaleRefPower = computeFullScaleRefPower(config);
results = runCompressionSim(config, fullScaleRefPower, ...
    sprintf('coloradar - frame %d', FRAME_INDEX), cube);

%% --- summary -------------------------------------------------------
fprintf('\n================================================================\n');
fprintf('  COLORADAR CASCADE: COMPRESSION SUMMARY (frame %d)\n', FRAME_INDEX);
fprintf('================================================================\n');
printRow = @(name, m) fprintf('  %-8s %6.2f %7.2f %7.2f %11.3f %9.3f\n', ...
    name, m.CR, m.FN_pct, m.FP_pct, m.NF_dBFS, m.SNR_dB);
fprintf('  %-8s %6s %7s %7s %11s %9s\n', ...
    'Algo', 'CR', 'FN%', 'FP%', 'NF dBFS', 'SNR dB');
printRow('FP16', results.metricsFP16);
printRow('DRHEfp16', results.metricsDRHEfp16);
printRow('FX16', results.metricsFX16);
printRow('DRHE', results.metricsDRHE);
printRow('BAQ', results.metricsBAQ);

printKiemReference();

fprintf('\n  Interpretation:\n');
fprintf('   * %d ref detections in the cascade NCI image.\n', results.refDetections);
fprintf('   * DRHE (FX16) compression ratio = %.2f; DRHEfp16 = %.2f.\n', ...
    results.metricsDRHE.CR, results.metricsDRHEfp16.CR);
fprintf('     contains coherent clutter / phase noise / multipath, which\n');
fprintf('     DRHE compresses unlike pure AWGN -> typically CR markedly above 1.\n');
fprintf('   * Compare against the synthetic Kiem-realistic scene (CR ~ 1.1):\n');
fprintf('     the gap is the "real-data structure" the AWGN simulator does not model.\n');

%% --- plots ---------------------------------------------------------
plotProcessingStages(results.rangeFFTData, results.dopplerFFTRef, results.rdMapRef, config, axesInfo);
plotCompressionComparison(results.rdMapFP16, results.rdMapFX16, config, fullScaleRefPower, axesInfo);

fprintf('\n================================================================\n');
fprintf('  COLORADAR RUN COMPLETE\n');
fprintf('================================================================\n');
