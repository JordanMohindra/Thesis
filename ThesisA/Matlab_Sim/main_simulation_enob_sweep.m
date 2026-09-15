%% ENOB Sweep: Kiem Hardware vs Future Work Comparison
%  Runs the ColoRadar compression pipeline at multiple ENOB (effective
%  number of bits) settings to compare:
%
%    ENOB < 16  →  simulates Kiem's FPGA hardware: the 16-bit fixed-point
%                  FFT accumulates truncation error at every butterfly
%                  stage, reducing the effective precision below 16 bits.
%
%    ENOB = 16  →  simulates Kiem's future work: a floating-point FFT
%                  produces clean output, which is then quantised to int16
%                  in a single step (no accumulated truncation).
%
%  In both cases the DRHE coder operates on the same int16 code grid, so
%  the compression ratio is expected to stay roughly constant while the
%  fidelity (FN%, FP%) improves as ENOB increases.
%
%  The script also includes the FP16/DRHEfp16 paths for reference (full
%  floating-point storage) to show why Kiem proposed fixed-point storage
%  with floating-point arithmetic, not full-float.
%
%  See also: MAIN_SIMULATION_COLORADAR, RUNCOMPRESSIONSIM, COMPRESS_FX16.

clear; clc; close all;

%% ============ CONFIGURATION (edit these) ==============================
FRAME_INDEX = 0;              % which frame_<N>.bin to load
TX_SELECT   = 1:12;           % which TX antennas to use (1:12 = all)
REMOVE_DC   = true;           % subtract per-ramp mean per channel

% ENOB values to sweep: low values simulate hardware accumulated
% truncation; 16 = clean single-step quantisation (float FFT)
ENOB_VALUES = [8, 9, 10, 11, 12, 13, 14, 15, 16];
% ======================================================================

%% --- locate and load the frame (once) ---------------------------------
candidatePaths = { ...
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
    error('enob_sweep:notFound', ...
          'Frame file frame_%d.bin not found in candidate directories.', FRAME_INDEX);
end

fprintf('================================================================\n');
fprintf('  ENOB SWEEP: Kiem Hardware vs Future Work\n');
fprintf('  ColoRadar frame %d, TX = %s\n', FRAME_INDEX, mat2str(TX_SELECT));
fprintf('================================================================\n');

% Load with ENOB=16 initially (we override per iteration)
opts = struct( ...
    'txSelect',          TX_SELECT, ...
    'removeDC',          REMOVE_DC, ...
    'fx16EffectiveBits', 16);
[cube, config, ~] = loadColoRadarFrame(binFile, opts);
fullScaleRefPower = computeFullScaleRefPower(config);

%% --- run the sweep ----------------------------------------------------
nSweep = numel(ENOB_VALUES);
rows = struct([]);

for k = 1:nSweep
    enob = ENOB_VALUES(k);
    config.fx16EffectiveBits = enob;

    fprintf('\n--- ENOB = %d ---\n', enob);
    rng(42);
    r = runCompressionSim(config, fullScaleRefPower, ...
        sprintf('ENOB=%d', enob), cube);

    rows(k).enob = enob;
    rows(k).res  = r;
end

%% --- results table ----------------------------------------------------
fprintf('\n================================================================\n');
fprintf('  ENOB SWEEP RESULTS (ColoRadar frame %d)\n', FRAME_INDEX);
fprintf('================================================================\n');
fprintf('  Interpretation of rows:\n');
fprintf('    ENOB  8-15 → simulates Kiem''s FPGA (fixed-point FFT artifacts)\n');
fprintf('    ENOB  16   → simulates Kiem''s future work (float FFT, clean int16)\n');
fprintf('    FP16/DRHEfp16 columns show the full-float reference\n');
fprintf('----------------------------------------------------------------\n');

% Header
fprintf('  %4s | %6s %6s %6s | %6s %6s %6s | %6s %6s | %6s %6s\n', ...
    'ENOB', ...
    'CR', 'FN%', 'FP%', ...       % DRHE (FX16)
    'CR', 'FN%', 'FP%', ...       % FP16 (no DRHE)
    'CR', 'FN%', ...               % DRHEfp16
    'NF_fx', 'NF_fp');            % noise floors
fprintf('  %4s | %6s %6s %6s | %6s %6s %6s | %6s %6s | %6s %6s\n', ...
    '----', ...
    '------', '------', '------', ...
    '------', '------', '------', ...
    '------', '------', ...
    '------', '------');
fprintf('  %4s   %s                      %s                    %s\n', ...
    '', '--- DRHE (FX16) ---', '--- FP16 ---', '--- DRHEfp16 ---');

for k = 1:nSweep
    r = rows(k).res;
    fprintf('  %4d | %6.2f %6.2f %6.2f | %6.2f %6.2f %6.2f | %6.2f %6.2f | %6.1f %6.1f\n', ...
        rows(k).enob, ...
        r.metricsDRHE.CR,     r.metricsFX16.FN_pct,      r.metricsFX16.FP_pct, ...
        r.metricsFP16.CR,     r.metricsFP16.FN_pct,      r.metricsFP16.FP_pct, ...
        r.metricsDRHEfp16.CR, r.metricsDRHEfp16.FN_pct, ...
        r.metricsDRHE.NF_dBFS, r.metricsFP16.NF_dBFS);
end

fprintf('================================================================\n');

%% --- plots ------------------------------------------------------------
figure('Name', 'ENOB Sweep', 'NumberTitle', 'off', 'Position', [80 80 1200 800]);

enobs = [rows.enob];
cr_drhe     = arrayfun(@(r) r.res.metricsDRHE.CR,     rows);
fn_fx16     = arrayfun(@(r) r.res.metricsFX16.FN_pct,  rows);
fp_fx16     = arrayfun(@(r) r.res.metricsFX16.FP_pct,  rows);
cr_drhefp16 = arrayfun(@(r) r.res.metricsDRHEfp16.CR, rows);
nf_drhe     = arrayfun(@(r) r.res.metricsDRHE.NF_dBFS, rows);
snr_drhe    = arrayfun(@(r) r.res.metricsDRHE.SNR_dB,  rows);

% (1) Compression Ratio vs ENOB
subplot(2,2,1);
plot(enobs, cr_drhe, 'b-o', 'LineWidth', 1.8, 'MarkerSize', 7); hold on;
yline(cr_drhefp16(1), 'r--', 'DRHEfp16', 'LineWidth', 1.2, 'LabelHorizontalAlignment', 'left');
hold off; grid on;
xlabel('Effective Number of Bits (ENOB)');
ylabel('Compression Ratio');
title('DRHE Compression Ratio vs ENOB');
xlim([min(enobs)-0.5, max(enobs)+0.5]);

% (2) False Negatives / False Positives vs ENOB
subplot(2,2,2);
yyaxis left;
plot(enobs, fn_fx16, 'b-o', 'LineWidth', 1.8, 'MarkerSize', 7);
ylabel('False Negatives (%)');
yyaxis right;
plot(enobs, fp_fx16, 'r-s', 'LineWidth', 1.8, 'MarkerSize', 7);
ylabel('False Positives (%)');
grid on;
xlabel('Effective Number of Bits (ENOB)');
title('Detection Error vs ENOB');
legend('FN%', 'FP%', 'Location', 'northeast');
xlim([min(enobs)-0.5, max(enobs)+0.5]);

% (3) Noise Floor vs ENOB
subplot(2,2,3);
plot(enobs, nf_drhe, 'b-o', 'LineWidth', 1.8, 'MarkerSize', 7);
grid on;
xlabel('Effective Number of Bits (ENOB)');
ylabel('Noise Floor (dBFS)');
title('Noise Floor vs ENOB');
xlim([min(enobs)-0.5, max(enobs)+0.5]);

% (4) CR vs FN% trade-off (Pareto frontier)
subplot(2,2,4);
plot(fn_fx16, cr_drhe, 'b-o', 'LineWidth', 1.8, 'MarkerSize', 7); hold on;
for k = 1:nSweep
    text(fn_fx16(k)+0.1, cr_drhe(k)+0.03, sprintf('%d', enobs(k)), 'FontSize', 8);
end
plot(0, cr_drhefp16(1), 'r*', 'MarkerSize', 12, 'LineWidth', 2);
text(0.15, cr_drhefp16(1), 'DRHEfp16', 'Color', 'r', 'FontSize', 9);
hold off; grid on;
xlabel('False Negatives (%)');
ylabel('Compression Ratio');
title('Pareto Frontier: CR vs Fidelity');

sgtitle(sprintf('ENOB Sweep — Kiem Hardware vs Future Work (frame %d)', FRAME_INDEX));

fprintf('\n  KEY TAKEAWAY:\n');
fprintf('    Compare ENOB=16 (float FFT, Kiem future work) to lower ENOB\n');
fprintf('    (fixed-point FFT, Kiem hardware). CR should stay similar while\n');
fprintf('    FN%%/FP%% improves — confirming the future work hypothesis.\n');
fprintf('    DRHEfp16 (full float) is shown for reference: CR ≈ 1.\n');
fprintf('================================================================\n');
