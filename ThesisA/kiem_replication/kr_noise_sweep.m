%% KR_NOISE_SWEEP
%  How the compression ratio of each method depends on the noise floor of
%  the simulated scene (Kiem Table 3.2 scene, one transmitter), and where
%  Kiem's two published operating points sit on that curve:
%    - his simulated scene: noise after NCI = -75 dBFS          [Table 3.2]
%    - his real-data result: NF = -70.7 dBFS with DRHE CR 3.25  [Table 3.5]
%  The chain is otherwise exactly run_kiem_replication.m.
%  Output: results/noise_sweep.csv and results/fig_noise_sweep.png

clear; close all;
here = fileparts(mfilename('fullpath')); addpath(here);
outDir = fullfile(here, 'results'); if ~exist(outDir, 'dir'), mkdir(outDir); end
cfg = kr_config('sim');
NF = -140:5:-60;
names = {'DRHE_fixed', 'DRHE_RLE', 'DRHE_noRLE', 'LPC_FFT', 'LPC_FFT_ideal', 'NoPred', 'NoPred_RLE', 'LPC_raw'};
T = zeros(numel(NF), numel(names)); sd = zeros(size(NF)); nfm = sd; fn = sd; fp = sd;
for i = 1:numel(NF)
    r = kr_run_scene(cfg, struct('lite', true, 'noiseNF', NF(i)));
    for j = 1:numel(names), T(i, j) = r.metrics.(names{j}).CR; end
    sd(i) = r.fx16.noiseOnlyStd; nfm(i) = r.metrics.FX16.NF;
    fn(i) = r.metrics.FX16.FN_pct; fp(i) = r.metrics.FX16.FP_pct;
    fprintf('NF %6.1f (meas %6.1f) noise std %8.2f LSB | DRHE %5.2f  DRHE+RLE %5.2f  LPC %5.2f  NoPred %5.2f  LPCraw %5.2f\n', ...
        NF(i), nfm(i), sd(i), T(i,1), T(i,2), T(i,4), T(i,6), T(i,8));
end
fid = fopen(fullfile(outDir, 'noise_sweep.csv'), 'w');
fprintf(fid, 'NF_target_dBFS,NF_measured_dBFS,FX16_noise_std_LSB,FX16_FN_pct,FX16_FP_pct,%s\n', strjoin(names, ','));
for i = 1:numel(NF)
    fprintf(fid, '%g,%.3f,%.4f,%.3f,%.3f%s\n', NF(i), nfm(i), sd(i), fn(i), fp(i), sprintf(',%.4f', T(i, :)));
end
fclose(fid);

f = figure('Visible', 'off', 'Position', [100 100 820 480]);
% x axis: the noise floor the scene was generated with. (Below about -115 dBFS
% the FX16 noise rounds to zero and a measured floor no longer exists.)
plot(NF, T(:,1), 'o-', NF, T(:,2), 's-', NF, T(:,4), 'd-', NF, T(:,6), 'k--', NF, T(:,8), 'x:', 'LineWidth', 1.2);
ylim([0 6]);
hold on; grid on;
plot(-70.691, 3.25, 'rp', 'MarkerSize', 14, 'MarkerFaceColor', 'r');
xline(-75, 'r:');
text(-74.5, 0.25, 'Kiem Table 3.2 noise (-75 dBFS)', 'Color', 'r');
text(-60.5, 3.62, 'Kiem, real data (NF -70.7, CR 3.25)', 'Color', 'r', 'HorizontalAlignment', 'right');
text(-99.5, 5.8, '\leftarrow RLE CR rises to 82 as the noise vanishes', 'Color', [0.85 0.33 0.1], 'HorizontalAlignment', 'left');
yline(3.25, 'r:');
xlabel('noise floor after NCI (dBFS, full-scale sinusoid = 0)'); ylabel('compression ratio');
legend('DRHE, fixed dictionary (HW)', 'DRHE, R4S4 + RLE, ideal', 'LPC slow time, fixed dict', ...
       'no prediction, fixed dict', 'LPC-Huffman raw ADC [25], p=10', 'Location', 'southwest');
title('Kiem Table 3.2 scene: compression ratio against noise floor');
print(f, fullfile(outDir, 'fig_noise_sweep.png'), '-dpng', '-r120'); close(f);
