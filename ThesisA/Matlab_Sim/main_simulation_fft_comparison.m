%% FFT Arithmetic Comparison: Fixed-Point FFT vs Floating-Point FFT
%  Directly compares the three scenarios to isolate where quantisation
%  error comes from:
%
%    (A) Float FFT + Float storage  (FP16 baseline)
%    (B) Float FFT + Fixed storage  (current FX16 = Kiem's future work)
%    (C) Fixed FFT + Fixed storage  (simulated Kiem hardware via rangeFFT_fx16)
%
%  Scenario (B) is what your current pipeline already does: MATLAB's
%  double-precision fft() followed by int16 quantisation.
%
%  Scenario (C) uses rangeFFT_fx16.m, which simulates a 16-bit fixed-point
%  radix-2 FFT with truncation at every butterfly stage. This shows the
%  ADDITIONAL error introduced by fixed-point FFT arithmetic on top of the
%  int16 storage error.
%
%  By comparing (B) vs (C), you can directly measure Kiem's claim: that
%  switching the FFT to floating-point reduces quantisation error while
%  keeping the same DRHE compression ratio.
%
%  See also RANGEFFT, RANGEFFT_FX16, RUNCOMPRESSIONSIM.

clear; clc; close all;

%% ============ CONFIGURATION ==========================================
FRAME_INDEX = 0;
TX_SELECT   = 1:12;
REMOVE_DC   = true;
% ======================================================================

%% --- Load frame -------------------------------------------------------
dataDir = fullfile(fileparts(mfilename('fullpath')), '..', '..', ...
                   'Jordan''s Thesis', 'cascade', 'adc_samples', 'data');
binFile = fullfile(dataDir, sprintf('frame_%d.bin', FRAME_INDEX));
if exist(binFile, 'file') ~= 2
    error('fft_comparison:notFound', 'Frame not found: %s', binFile);
end

fprintf('================================================================\n');
fprintf('  FFT ARITHMETIC COMPARISON\n');
fprintf('  Float FFT vs Fixed-Point FFT on ColoRadar frame %d\n', FRAME_INDEX);
fprintf('================================================================\n');

opts = struct('txSelect', TX_SELECT, 'removeDC', REMOVE_DC, ...
              'fx16EffectiveBits', 16);
[cube, config, axesInfo] = loadColoRadarFrame(binFile, opts);
Pref = computeFullScaleRefPower(config);

%% --- Preprocessing (shared) -------------------------------------------
pre = preprocessing(cube, config);

%% === SCENARIO A: Float FFT + Float Storage (FP16 reference) ===========
fprintf('\n--- Scenario A: Float FFT + Float Storage (FP16) ---\n');
fftFloat = rangeFFT(pre, config);                      % double-precision FFT

compA = compress_fp16(fftFloat);
decA  = decompress_fp16(compA);
[detA, rdA, ~] = secondStageProcessing(decA, config);

% Reference (uncompressed double-precision)
[detRef, rdRef, dopRef] = secondStageProcessing(fftFloat, config);

%% === SCENARIO B: Float FFT + Fixed Storage (FX16, Kiem future work) ===
fprintf('--- Scenario B: Float FFT + Fixed Storage (FX16) ---\n');
% fftFloat already computed above (same double-precision FFT)

compB = compress_fx16(fftFloat, config);
decB  = decompress_fx16(compB);
[detB, rdB, ~] = secondStageProcessing(decB, config);

% DRHE on top of FX16
drheB = compress_drhe(compB, config);
decDrheB  = decompress_drhe(drheB);
[detDrheB, rdDrheB, ~] = secondStageProcessing(decDrheB, config);

%% === SCENARIO C: Fixed FFT + Fixed Storage (simulated Kiem hardware) ==
fprintf('--- Scenario C: Fixed-Point FFT + Fixed Storage (FX16) ---\n');
tic;
fftFixed = rangeFFT_fx16(pre, config);                 % FIXED-POINT FFT
fxFFTtime = toc;
fprintf('  rangeFFT_fx16 completed in %.1f seconds\n', fxFFTtime);

compC = compress_fx16(fftFixed, config);
decC  = decompress_fx16(compC);
[detC, rdC, ~] = secondStageProcessing(decC, config);

% DRHE on top of FX16 (fixed FFT)
drheC = compress_drhe(compC, config);
decDrheC  = decompress_drhe(drheC);
[detDrheC, rdDrheC, ~] = secondStageProcessing(decDrheC, config);

%% --- Metrics -----------------------------------------------------------
mA = evaluateMetrics(detRef, detA, rdRef, rdA, 1.0, Pref);
mB = evaluateMetrics(detRef, detB, rdRef, rdB, 1.0, Pref);
mC = evaluateMetrics(detRef, detC, rdRef, rdC, 1.0, Pref);
mDrheB = evaluateMetrics(detRef, detDrheB, rdRef, rdDrheB, drheB.CR, Pref);
mDrheC = evaluateMetrics(detRef, detDrheC, rdRef, rdDrheC, drheC.CR, Pref);

%% --- FFT-level error analysis ------------------------------------------
% Compare the raw FFT outputs to measure how much error the fixed-point
% FFT introduces BEFORE any storage quantisation
fftErr_float = fftFloat - fftFloat;  % zero (trivially)
fftErr_fixed = fftFixed - fftFloat;  % error from fixed-point FFT

fftRelRMS_fixed = 100 * sqrt(mean(abs(fftErr_fixed(:)).^2)) / ...
                        sqrt(mean(abs(fftFloat(:)).^2));

% int16 code utilisation
codesB = double([compB.real_part(:); compB.imag_part(:)]);
codesC = double([compC.real_part(:); compC.imag_part(:)]);
useB = 100 * max(abs(codesB)) / 32767;
useC = 100 * max(abs(codesC)) / 32767;

%% --- Results table -----------------------------------------------------
fprintf('\n================================================================\n');
fprintf('  FFT ARITHMETIC COMPARISON RESULTS (frame %d)\n', FRAME_INDEX);
fprintf('================================================================\n');
fprintf('  Reference detections: %d\n', sum(detRef(:)));
fprintf('\n');
fprintf('  %-35s %6s %6s %6s %8s %8s\n', ...
    'Scenario', 'CR', 'FN%', 'FP%', 'NF dBFS', 'SNR dB');
fprintf('  %-35s %6s %6s %6s %8s %8s\n', ...
    '-----------------------------------', '------', '------', '------', '--------', '--------');
fprintf('  %-35s %6.2f %6.2f %6.2f %8.1f %8.1f\n', ...
    '(A) Float FFT + Float store (FP16)', mA.CR, mA.FN_pct, mA.FP_pct, mA.NF_dBFS, mA.SNR_dB);
fprintf('  %-35s %6.2f %6.2f %6.2f %8.1f %8.1f\n', ...
    '(B) Float FFT + Fixed store (FX16)', mB.CR, mB.FN_pct, mB.FP_pct, mB.NF_dBFS, mB.SNR_dB);
fprintf('  %-35s %6.2f %6.2f %6.2f %8.1f %8.1f\n', ...
    '(C) Fixed FFT + Fixed store (FX16)', mC.CR, mC.FN_pct, mC.FP_pct, mC.NF_dBFS, mC.SNR_dB);
fprintf('\n');
fprintf('  With DRHE compression:\n');
fprintf('  %-35s %6.2f %6.2f %6.2f %8.1f %8.1f\n', ...
    '(B+DRHE) Float FFT + DRHE', mDrheB.CR, mDrheB.FN_pct, mDrheB.FP_pct, mDrheB.NF_dBFS, mDrheB.SNR_dB);
fprintf('  %-35s %6.2f %6.2f %6.2f %8.1f %8.1f\n', ...
    '(C+DRHE) Fixed FFT + DRHE', mDrheC.CR, mDrheC.FN_pct, mDrheC.FP_pct, mDrheC.NF_dBFS, mDrheC.SNR_dB);

fprintf('\n  --- FFT-Level Error Analysis ---\n');
fprintf('  Fixed-point FFT relative RMS error: %.4f%%\n', fftRelRMS_fixed);
fprintf('  int16 code utilisation (float FFT):  %.2f%%\n', useB);
fprintf('  int16 code utilisation (fixed FFT):  %.2f%%\n', useC);
fprintf('  DRHE CR (float FFT): %.3f\n', drheB.CR);
fprintf('  DRHE CR (fixed FFT): %.3f\n', drheC.CR);
fprintf('================================================================\n');

fprintf('\n  KEY COMPARISONS:\n');
fprintf('    (B) vs (C): Isolates the effect of FFT arithmetic.\n');
fprintf('      Same int16 storage, different FFT precision.\n');
fprintf('      If (C) has more FN/FP than (B), the fixed-point FFT\n');
fprintf('      truncation is causing additional error beyond storage.\n');
fprintf('    (B) vs (A): Isolates the effect of storage format.\n');
fprintf('      Same float FFT, different storage (int16 vs half-float).\n');
fprintf('    (B+DRHE) vs (C+DRHE): Does the FFT arithmetic affect CR?\n');
fprintf('      Kiem''s claim: CR stays similar, FN/FP improves.\n');

%% --- Plots -------------------------------------------------------------
figure('Name', 'FFT Arithmetic Comparison', 'NumberTitle', 'off', ...
       'Position', [60 60 1500 900]);

refDB = 10*log10(rdRef/Pref + eps);
cmax = max(refDB(:));
cmin = cmax - 60;

useReal = ~isempty(axesInfo) && isfield(axesInfo,'realData') && axesInfo.realData;
if useReal
    xAx = axesInfo.velAxis; yAx = axesInfo.rangeAxis;
    xLbl = 'Velocity (m/s)'; yLbl = 'Range (m)';
    refDB = fftshift(refDB, 2);
else
    xAx = 0:config.numRamps-1; yAx = 0:size(rdRef,1)-1;
    xLbl = 'Doppler bin'; yLbl = 'Range bin';
end

% (1) Reference RD map
subplot(2,3,1);
imagesc(xAx, yAx, refDB); axis xy; colormap(jet); colorbar; clim([cmin cmax]);
xlabel(xLbl); ylabel(yLbl);
title('Reference (double-precision)');
if useReal; applyLims(axesInfo); end

% (2) Float FFT error (B vs Ref)
rdBdb = 10*log10(rdB/Pref + eps);
if useReal; rdBdb = fftshift(rdBdb, 2); end
subplot(2,3,2);
imagesc(xAx, yAx, rdBdb - refDB); axis xy; colorbar;
xlabel(xLbl); ylabel(yLbl);
title({'(B) Float FFT + Fixed store'; 'Error vs reference [dB]'});
if useReal; applyLims(axesInfo); end

% (3) Fixed FFT error (C vs Ref)
rdCdb = 10*log10(rdC/Pref + eps);
if useReal; rdCdb = fftshift(rdCdb, 2); end
subplot(2,3,3);
imagesc(xAx, yAx, rdCdb - refDB); axis xy; colorbar;
xlabel(xLbl); ylabel(yLbl);
title({'(C) Fixed FFT + Fixed store'; 'Error vs reference [dB]'});
if useReal; applyLims(axesInfo); end

% (4) Raw FFT magnitude comparison: one range bin across ramps
subplot(2,3,4);
midBin = round(size(fftFloat,1) * 0.4);  % pick a mid-range bin
magFloat = abs(fftFloat(midBin, :, 1));
magFixed = abs(fftFixed(midBin, :, 1));
plot(1:numel(magFloat), magFloat, 'b-', 'LineWidth', 1.2); hold on;
plot(1:numel(magFixed), magFixed, 'r--', 'LineWidth', 1.2); hold off;
xlabel('Ramp index'); ylabel('|FFT output|');
title(sprintf('Range bin %d: FFT output magnitude', midBin));
legend('Float FFT', 'Fixed FFT', 'Location', 'best');
grid on;

% (5) Histogram of int16 codes: float vs fixed FFT
subplot(2,3,5);
histogram(abs(codesB), 100, 'FaceAlpha', 0.5, 'FaceColor', 'b'); hold on;
histogram(abs(codesC), 100, 'FaceAlpha', 0.5, 'FaceColor', 'r'); hold off;
set(gca, 'YScale', 'log');
xlabel('|int16 code|'); ylabel('Count (log)');
title('int16 code distribution after compress\_fx16');
legend('Float FFT → FX16', 'Fixed FFT → FX16', 'Location', 'northeast');
grid on;

% (6) Bar chart summary
subplot(2,3,6);
scenarios = categorical({'A: FP16', 'B: FloatFFT+FX16', 'C: FixedFFT+FX16', ...
                         'B+DRHE', 'C+DRHE'});
scenarios = reordercats(scenarios, {'A: FP16', 'B: FloatFFT+FX16', 'C: FixedFFT+FX16', ...
                                    'B+DRHE', 'C+DRHE'});
fn_vals = [mA.FN_pct, mB.FN_pct, mC.FN_pct, mDrheB.FN_pct, mDrheC.FN_pct];
cr_vals = [1.0, 1.0, 1.0, mDrheB.CR, mDrheC.CR];

yyaxis left;
bar(scenarios, fn_vals, 0.6, 'FaceColor', [0.2 0.4 0.8]);
ylabel('False Negatives (%)');
yyaxis right;
plot(scenarios, cr_vals, 'r-o', 'LineWidth', 2, 'MarkerSize', 8);
ylabel('Compression Ratio');
title('Summary: FN% and CR across scenarios');
grid on;

sgtitle(sprintf('FFT Arithmetic Comparison (ColoRadar frame %d)', FRAME_INDEX));

fprintf('\n  Plots generated.\n');
fprintf('================================================================\n');

%% ======================================================================= %%
function applyLims(axesInfo)
    ylim([0 axesInfo.rangeMaxPlot]);
    if ~isempty(axesInfo.velMaxPlot)
        xlim([-axesInfo.velMaxPlot axesInfo.velMaxPlot]);
    end
end
