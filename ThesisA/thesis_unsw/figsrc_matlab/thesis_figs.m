%THESIS_FIGS  MATLAB versions of the report figures that were not already
%  produced by Matlab_Sim/make_poster_figs.m:
%    figs/fig_bits.pdf      bits per value through the compressor (Section 10.3)
%    figs/fig_kr_sweep.pdf  CR against noise floor on Kiem's rebuilt scene (Section 9.2)
%  The other report figures (fig_stage1, fig_cr_bars, fig_cr_frames, fig_residual,
%  fig_input, fig_timing, fig_resources) come from make_poster_figs.m.
%  Run from anywhere:  run('D:\Thesis\ThesisA\thesis_unsw\figsrc_matlab\thesis_figs.m')

here   = fileparts(mfilename('fullpath'));
outDir = fullfile(here, '..', 'figs');
repl   = fullfile(here, '..', '..', 'kiem_replication', 'results');

ACC   = [47 93 124] / 255;    % blue
WARM  = [181 85 63] / 255;    % red
SLATE = [138 143 152] / 255;
GOLD  = [176 138 74] / 255;
FONT  = 'Times New Roman';

%% ---------------- fig_bits: bits per value through the compressor ----------------
% Bits per (real or imaginary) value, 50 frames, 4 RX, from the Stage 2 ratios.
lab  = {{'int16', 'container'}, {'occupied', 'range'}, {'Huffman,', 'no prediction'}, ...
        {'+ prediction'}, {'+ re-derived', 'dictionary'}};
drhe = [16, 9.77, 16/3.479, 16/3.751, 16/4.218];
lpc  = [NaN, NaN, NaN, 16/3.697, 16/4.404];
cols = [51 65 79; 107 123 140; 64 96 125; 47 109 79; 122 163 59] / 255;

f = figure('Color', 'w', 'Units', 'centimeters', 'Position', [2 2 15.5 7.2]);
ax = axes(f); hold(ax, 'on');
w = 0.3;
for i = 1:5
    if isnan(lpc(i))
        bar(ax, i, drhe(i), 0.5, 'FaceColor', cols(i, :), 'EdgeColor', 'none');
        text(ax, i, drhe(i) + 0.35, sprintf('%.2f', drhe(i)), 'HorizontalAlignment', 'center', ...
             'FontName', FONT, 'FontSize', 8);
    else
        hD = bar(ax, i - w/2, drhe(i), w, 'FaceColor', cols(i, :), 'EdgeColor', 'none');
        hL = bar(ax, i + w/2, lpc(i), w, 'FaceColor', cols(i, :), 'FaceAlpha', 0.45, ...
                 'EdgeColor', cols(i, :), 'LineWidth', 0.8);
        text(ax, i - w/2, drhe(i) + 0.35, sprintf('%.2f', drhe(i)), 'HorizontalAlignment', 'center', ...
             'FontName', FONT, 'FontSize', 7.5);
        text(ax, i + w/2, lpc(i) + 0.35, sprintf('%.2f', lpc(i)), 'HorizontalAlignment', 'center', ...
             'FontName', FONT, 'FontSize', 7.5);
        if i == 4, legDRHE = hD; legLPC = hL; end
    end
end
for i = 2:5   % reduction factor between successive stages (DRHE)
    text(ax, i - 0.5, (drhe(i-1) + drhe(i)) / 2 + 1.2, sprintf('\\div%.2f', drhe(i-1) / drhe(i)), ...
         'HorizontalAlignment', 'center', 'FontName', FONT, 'FontSize', 8, 'Color', [0.3 0.3 0.3]);
end
set(ax, 'XTick', 1:5, 'XTickLabel', {}, 'FontName', FONT, 'FontSize', 8.5, 'Box', 'off', ...
    'YGrid', 'on', 'GridAlpha', 0.2, 'TickDir', 'out');
for i = 1:5   % two-line category labels under the axis
    text(ax, i, -0.6, lab{i}, 'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', ...
         'FontName', FONT, 'FontSize', 8.5);
end
ylabel(ax, 'bits per value'); ylim(ax, [0 18]); xlim(ax, [0.4 5.6]);
legend(ax, [legDRHE legLPC], {'DRHE', 'LPC'}, 'Box', 'off', 'Location', 'northeast', 'FontSize', 8.5);
exportgraphics(f, fullfile(outDir, 'fig_bits.pdf'), 'ContentType', 'vector', 'BackgroundColor', 'white');
close(f);

%% ---------------- fig_kr_sweep: CR against noise floor on Kiem's scene ----------------
hw = readtable(fullfile(repl, 'noise_sweep.csv'));        % Kiem's FFT-core scaling
pk = readtable(fullfile(repl, 'noise_sweep_peak.csv'));   % full-scale scaling (this thesis)
m  = hw.NF_target_dBFS >= -120;
% this thesis's own chain on synthetic scenes of Kiem's kind (Matlab_Sim logs)
early_nf = [-71.03, -70.70, -85.37, -95.08, -78.41, -82.45, -88.21, -90.03];
early_cr = [1.11, 1.10, 1.56, 2.08, 1.30, 1.44, 1.70, 1.79];

f = figure('Color', 'w', 'Units', 'centimeters', 'Position', [2 2 15.5 10]);
ax = axes(f); hold(ax, 'on');
h1 = plot(ax, hw.NF_target_dBFS(m), hw.DRHE_fixed(m), '-o', 'Color', ACC, 'MarkerSize', 3.5, ...
          'MarkerFaceColor', ACC, 'LineWidth', 1.1);
h2 = plot(ax, pk.NF_target_dBFS, pk.DRHE_fixed, '-s', 'Color', WARM, 'MarkerSize', 3.5, ...
          'MarkerFaceColor', WARM, 'LineWidth', 1.1);
h3 = plot(ax, hw.NF_target_dBFS(m), hw.LPC_raw(m), ':x', 'Color', SLATE, 'MarkerSize', 4, 'LineWidth', 1.1);
h4 = plot(ax, early_nf, early_cr, 'd', 'MarkerSize', 5, 'MarkerEdgeColor', GOLD, ...
          'MarkerFaceColor', 'w', 'LineWidth', 1.2);
h5 = plot(ax, -70.691, 3.25, 'p', 'MarkerSize', 12, 'MarkerFaceColor', [0.75 0.22 0.17], ...
          'MarkerEdgeColor', [0.75 0.22 0.17]);
yline(ax, 3.25, ':', 'Color', [0.75 0.22 0.17], 'LineWidth', 0.8, 'HandleVisibility', 'off');
xline(ax, -75, '--', 'Color', [0.4 0.4 0.4], 'LineWidth', 0.8, 'HandleVisibility', 'off');
text(ax, -74.4, 3.95, {'Kiem''s scene:', '-75 dBFS'}, 'FontName', FONT, 'FontSize', 8, 'Color', [0.3 0.3 0.3]);
set(ax, 'FontName', FONT, 'FontSize', 9, 'Box', 'off', 'XGrid', 'on', 'YGrid', 'on', ...
    'GridAlpha', 0.2, 'TickDir', 'out');
xlabel(ax, 'noise floor after non-coherent integration (dBFS)');
ylabel(ax, 'compression ratio');
xlim(ax, [-121 -59]); ylim(ax, [0 4.3]);
legend(ax, [h1 h2 h3 h4 h5], {'DRHE, Kiem''s FFT-core scaling', ...
    'DRHE, full-scale scaling (this thesis)', 'LPC-Huffman on raw ADC [Meucci]', ...
    'this thesis''s chain, synthetic scenes', 'Kiem, his Table 3.5 (real data)'}, ...
    'Box', 'off', 'FontSize', 8, 'NumColumns', 2, 'Location', 'southoutside');
exportgraphics(f, fullfile(outDir, 'fig_kr_sweep.pdf'), 'ContentType', 'vector', 'BackgroundColor', 'white');
close(f);
fprintf('thesis_figs: wrote fig_bits.pdf and fig_kr_sweep.pdf to %s\n', outDir);
