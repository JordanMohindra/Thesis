%THESIS_FIGS_RESULTS  Report versions of the data figures of Chapters 5 and 7.
%  The poster keeps its own PNGs (Matlab_Sim/make_poster_figs.m, with titles
%  and plain-language labels). These are the same data drawn for the report:
%  no titles inside the plots, Times New Roman, labels placed by hand so that
%  nothing overlaps, vector PDF.
%    figs/fig_input_report.png  one range-FFT frame, receiver 1     (Figure 5.1; raster)
%    figs/fig_stage1.pdf     ratio against missed detections          (Figure 7.1)
%    figs/fig_cr_bars.pdf    where the compression comes from         (Figure 7.2)
%    figs/fig_residual.pdf   S4 categories of raw codes and residuals  (Figure 7.3)
%    figs/fig_cr_frames.pdf  ratio of each frame                       (Figure 7.4)
%    figs/fig_timing.pdf     time per frame on the board              (Figure 7.5)
%    figs/fig_resources.pdf  share of the chip per core               (Figure 7.6)
%  Data: ../../poster/poster_results.mat (the cached Stage 1 and Stage 2
%  results of make_poster_figs.m) and ../../poster/poster_hardware.csv (board
%  timing and post-route resources). fig_input reads ColoRadar frame 0.
%  Run:  run('C:\Users\mohin\Thesis\ThesisA\thesis_unsw\figsrc_matlab\thesis_figs_results.m')

here   = fileparts(mfilename('fullpath'));
outDir = fullfile(here, '..', 'figs');
poster = fullfile(here, '..', '..', 'poster');
addpath(fullfile(here, '..', '..', 'Matlab_Sim'));

FONT = 'Times New Roman'; FS = 9;
BLUE = [0 114 189] / 255; ORANGE = [217 83 25] / 255; GREY = [0.62 0.62 0.62];
GREEN = [0.47 0.67 0.19]; DARK = [0.30 0.30 0.30]; SEL = [0.18 0.49 0.20];
W = 13;                                    % cm; included at 0.8\textwidth
style = @(ax) set(ax, 'FontName', FONT, 'FontSize', FS, 'Box', 'on', 'TickDir', 'out', ...
                  'XGrid', 'on', 'YGrid', 'on', 'GridAlpha', 0.15, 'LineWidth', 0.6);
newfig = @(h) figure('Color', 'w', 'Units', 'centimeters', 'Position', [2 2 W h], 'Visible', 'off');
save_pdf = @(f, name) exportgraphics(f, fullfile(outDir, name), 'ContentType', 'vector', ...
                                     'BackgroundColor', 'white');

C = load(fullfile(poster, 'poster_results.mat'));
T1 = C.stage1.T; S2 = C.stage2;
HW = readtable(fullfile(poster, 'poster_hardware.csv'));

%% ---- Figure 7.1: ratio against missed detections ----
gv = @(name, col) T1.(col)(strcmp(T1.Algorithm, name));
f = newfig(8.2); ax = axes(f); hold(ax, 'on'); style(ax);
fxFN = gv('FX16', 'FN_pct');
patch(ax, [3 4.25 4.25 3], [-1.5 -1.5 fxFN + 1.6 fxFN + 1.6], [0.88 0.94 0.85], ...
      'EdgeColor', SEL, 'LineWidth', 0.6);
text(ax, 4.2, -0.4, {'ratio > 3, no loss', 'beyond FX16'}, 'HorizontalAlignment', 'right', ...
     'VerticalAlignment', 'bottom', 'FontName', FONT, 'FontSize', 8, 'Color', SEL);
grpRef = {'FP16', 'DRHEfp16', 'FX16'}; grpLossy = {'BAQ', 'RDVLE', 'RDVLE_UDRE'}; grpSel = {'DRHE', 'LPC_Huffman'};
pt = @(n, mk, col, sz) plot(ax, gv(n, 'CR'), gv(n, 'FN_pct'), mk, 'MarkerSize', sz, ...
                            'MarkerFaceColor', col, 'MarkerEdgeColor', 'k', 'LineWidth', 0.5);
for n = grpRef,   hR = pt(n{1}, 'o', GREY, 6); end
for n = grpLossy, hY = pt(n{1}, 's', ORANGE, 6); end
for n = grpSel,   hS = pt(n{1}, 'd', BLUE, 7); end
lab = @(x, y, s, ha) text(ax, x, y, s, 'HorizontalAlignment', ha, 'FontName', FONT, 'FontSize', 8.5);
lab(gv('FX16', 'CR') + 0.08, gv('FX16', 'FN_pct') + 0.9, 'FX16', 'left');
lab(gv('DRHEfp16', 'CR') + 0.1, 1.1, 'FP16, DRHE fp16', 'left');
lab(gv('RDVLE', 'CR') + 0.08, gv('RDVLE', 'FN_pct'), 'RDVLE', 'left');
lab(gv('RDVLE_UDRE', 'CR') + 0.08, gv('RDVLE_UDRE', 'FN_pct'), 'RDVLE+UDRE', 'left');
lab(gv('BAQ', 'CR') - 0.08, gv('BAQ', 'FN_pct'), 'BAQ', 'right');
lab(3.62, fxFN + 3.2, sprintf('LPC %.2f, DRHE %.2f', gv('LPC_Huffman', 'CR'), gv('DRHE', 'CR')), 'right');
plot(ax, [3.62 3.69], [fxFN + 2.6 fxFN + 0.6], '-', 'Color', [0.3 0.3 0.3], 'LineWidth', 0.5);
xlim(ax, [0.8 4.25]); ylim(ax, [-1.5 32]);
xlabel(ax, 'compression ratio'); ylabel(ax, 'missed detections (%)');
legend(ax, [hR hY hS], {'reference formats', 'lossy', 'lossless (selected)'}, 'Location', 'east', ...
       'FontSize', 8, 'Box', 'off');
save_pdf(f, 'fig_stage1.pdf'); close(f);

%% ---- Figure 7.2: where the compression comes from ----
kiem  = huffman_tables('kiem');
dictD = huffman_tables('drhe_retrained'); dictL = huffman_tables('lpc_retrained');
crOf  = @(hist, dict, extra) S2.inputBits ./ (hist * (dict + (0:15))' + extra);
cr.none = crOf(S2.histNone, kiem, 0);
cr.dK = crOf(S2.histDRHE, kiem, 0);  cr.lK = crOf(S2.histLPC, kiem, S2.lpcOverhead);
cr.dN = crOf(S2.histDRHE, dictD, 0); cr.lN = crOf(S2.histLPC, dictL, S2.lpcOverhead);
base = mean(cr.none);
steps = [base, mean(cr.dK) - base, mean(cr.dN) - mean(cr.dK), mean(cr.dN);
         base, mean(cr.lK) - base, mean(cr.lN) - mean(cr.lK), mean(cr.lN)];
f = newfig(7.6); ax = axes(f); hold(ax, 'on'); style(ax); ax.XGrid = 'off';
xs = [1 2 3 4; 6 7 8 9]; w = 0.7; cl = {BLUE, ORANGE, GREEN, DARK}; h = gobjects(1, 4);
for a = 1:2
    s = steps(a, :); lo = [0, s(1), s(1) + s(2), 0]; hi = [s(1), s(1) + s(2), s(4), s(4)];
    for k = 1:4
        h(k) = patch(ax, xs(a, k) + w / 2 * [-1 1 1 -1], [lo(k) lo(k) hi(k) hi(k)], cl{k}, 'EdgeColor', 'k', 'LineWidth', 0.4);
    end
    for k = 1:3
        plot(ax, [xs(a, k) + w / 2, xs(a, k + 1) - w / 2], [hi(k) hi(k)], 'k:', 'LineWidth', 0.6);
    end
    txt = {sprintf('%.2f', s(1)), sprintf('+%.2f', s(2)), sprintf('+%.2f', s(3)), sprintf('%.2f', s(4))};
    for k = 1:4
        fw = 'normal'; if k == 4, fw = 'bold'; end
        text(ax, xs(a, k), hi(k) + 0.06, txt{k}, 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
             'FontName', FONT, 'FontSize', 8.5, 'FontWeight', fw);
    end
end
set(ax, 'XTick', [2.5 7.5], 'XTickLabel', {'DRHE', 'LPC'}); xlim(ax, [0.3 9.7]); ylim(ax, [0 5]);
ylabel(ax, 'compression ratio');
legend(ax, h, {'Huffman coder alone', '+ prediction', '+ re-derived dictionary', 'total'}, ...
       'Location', 'southoutside', 'Orientation', 'horizontal', 'FontSize', 8, 'Box', 'off');
save_pdf(f, 'fig_cr_bars.pdf'); close(f);

%% ---- Figure 7.3: S4 categories of the raw codes and of the residuals ----
hN = sum(S2.histNone, 1); hD = sum(S2.histDRHE, 1); hL = sum(S2.histLPC, 1);
pct = 100 * [hN / sum(hN); hD / sum(hD); hL / sum(hL)]';
kmax = 8;
f = newfig(7.2); ax = axes(f); hold(ax, 'on'); style(ax); ax.XGrid = 'off';
b = bar(ax, 0:kmax - 1, pct(1:kmax, :), 0.88, 'LineWidth', 0.4);
b(1).FaceColor = GREY; b(2).FaceColor = BLUE; b(3).FaceColor = ORANGE;
xlim(ax, [-0.6 kmax - 0.4]); ylim(ax, [0 40]);
xlabel(ax, 'size category S_4 (magnitude bits)'); ylabel(ax, 'share of values (%)');
legend(ax, {'FX16 codes, no prediction', 'DRHE residuals', 'LPC residuals'}, 'Location', 'northeast', ...
       'FontSize', 8, 'Box', 'off');
save_pdf(f, 'fig_residual.pdf'); close(f);

%% ---- Figure 7.4: ratio of each frame ----
f = newfig(6.8); ax = axes(f); hold(ax, 'on'); style(ax);
patch(ax, [-0.5 4.5 4.5 -0.5], [3.2 3.2 5 5], [0.93 0.93 0.93], 'EdgeColor', 'none', 'HandleVisibility', 'off');
text(ax, 2, 3.3, 'training', 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
     'FontName', FONT, 'FontSize', 7.5, 'Color', [0.35 0.35 0.35]);
p1 = plot(ax, S2.frame, cr.dN, '-o', 'MarkerSize', 3, 'LineWidth', 1.0, 'Color', BLUE, 'MarkerFaceColor', BLUE);
p2 = plot(ax, S2.frame, cr.lN, '-s', 'MarkerSize', 3, 'LineWidth', 1.0, 'Color', ORANGE, 'MarkerFaceColor', ORANGE);
xlim(ax, [-0.5 49.5]); ylim(ax, [3.2 5]);
xlabel(ax, 'frame'); ylabel(ax, 'compression ratio');
legend(ax, [p1 p2], {sprintf('DRHE (mean %.2f)', mean(cr.dN)), sprintf('LPC (mean %.2f)', mean(cr.lN))}, ...
       'Location', 'south', 'Orientation', 'horizontal', 'FontSize', 8, 'Box', 'off');
save_pdf(f, 'fig_cr_frames.pdf'); close(f);

%% ---- Figure 7.5: time per frame on the board ----
ms = @(cyc) cyc / 1e5;                     % 100 MHz clock
d = HW(strcmp(HW.Algorithm, 'DRHE'), :); l = HW(strcmp(HW.Algorithm, 'LPC'), :);
rows = {'DRHE encode', 'DRHE decode', 'LPC encode', 'LPC decode'};
vals = [ms(d.EncCyclesPerFrame), ms(d.DecCyclesPerFrame), ms(l.EncCyclesPerFrame), ms(l.DecCyclesPerFrame)];
cols = {BLUE, (BLUE + 1) / 2, ORANGE, (ORANGE + 1) / 2};
notes = {sprintf('%.2f ms; output %.0f %ss behind input', vals(1), d.EncLatencyCycles / 100, char(956)), ...
         sprintf('%.2f ms', vals(2)), ...
         sprintf('%.2f ms; output %.1f ms behind input', vals(3), ms(l.EncLatencyCycles)), ...
         sprintf('%.2f ms', vals(4))};
f = newfig(6.4); ax = axes(f); hold(ax, 'on'); style(ax); ax.YGrid = 'off';
for k = 1:4
    y = 5 - k;
    rectangle(ax, 'Position', [0, y - 0.3, vals(k), 0.6], 'FaceColor', cols{k}, 'EdgeColor', 'k', 'LineWidth', 0.4);
    text(ax, vals(k) + 0.12, y, notes{k}, 'FontName', FONT, 'FontSize', 8.5, 'VerticalAlignment', 'middle');
end
set(ax, 'YTick', 1:4, 'YTickLabel', fliplr(rows)); ylim(ax, [0.4 4.6]); xlim(ax, [0 8]);
xlabel(ax, 'time per frame (ms)');
save_pdf(f, 'fig_timing.pdf'); close(f);

%% ---- Figure 7.6: share of the chip per core ----
chip = [216960, 433920, 480, 1824];        % XCKU5P: LUT, FF, BRAM36, DSP
pick = [1 3 4];                            % LUT, BRAM, DSP
f = newfig(6.6);
tl = tiledlayout(f, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
for a = 1:2
    r = HW(a, :);
    e = [r.Encoder_LUT_FF_BRAM_DSP_1, r.Encoder_LUT_FF_BRAM_DSP_2, r.Encoder_LUT_FF_BRAM_DSP_3, r.Encoder_LUT_FF_BRAM_DSP_4] ./ chip;
    dd = [r.Decoder_LUT_FF_BRAM_DSP_1, r.Decoder_LUT_FF_BRAM_DSP_2, r.Decoder_LUT_FF_BRAM_DSP_3, r.Decoder_LUT_FF_BRAM_DSP_4] ./ chip;
    U = 100 * [e(pick); dd(pick); e(pick) + dd(pick)];
    ax = nexttile(tl); hold(ax, 'on'); style(ax); ax.XGrid = 'off';
    b = bar(ax, U, 0.85, 'LineWidth', 0.4);
    b(1).FaceColor = BLUE; b(2).FaceColor = ORANGE; b(3).FaceColor = [0.93 0.69 0.13];
    set(ax, 'XTick', 1:3, 'XTickLabel', {'encoder', 'decoder', 'both'}); ylim(ax, [0 30]);
    text(ax, 3 + b(1).XOffset, U(3, 1) + 0.5, sprintf('%.0f%%', U(3, 1)), 'HorizontalAlignment', 'center', ...
         'VerticalAlignment', 'bottom', 'FontName', FONT, 'FontSize', 8);
    title(ax, HW.Algorithm{a}, 'FontName', FONT, 'FontSize', FS, 'FontWeight', 'normal');
    if a == 1, ylabel(ax, 'share of the XCKU5P (%)'); end
end
lg = legend(ax, {'LUT', 'block RAM', 'DSP'}, 'Orientation', 'horizontal', 'FontSize', 8, 'Box', 'off');
lg.Layout.Tile = 'south';
save_pdf(f, 'fig_resources.pdf'); close(f);

%% ---- Figure 5.1: one range-FFT frame, receiver 1 ----
[dataDir, frameFiles] = find_coloradar_data('');
fi = find(arrayfun(@(dd) sscanf(dd.name, 'frame_%d.bin'), frameFiles) == 0, 1);
binFile = fullfile(dataDir, frameFiles(fi).name);
loadOpts = struct('txSelect', 1:12, 'removeDC', true, 'fx16EffectiveBits', 16);
[~, cube, config] = evalc('loadColoRadarFrame(binFile, loadOpts)');
fx = compress_fx16(rangeFFT(preprocessing(cube, config), config), config);
X = complex(double(fx.real_part(:, :, 1)), double(fx.imag_part(:, :, 1)));
f = newfig(8.4); ax = axes(f);
imagesc(ax, 0:size(X, 2) - 1, 0:size(X, 1) - 1, 20 * log10(abs(X) + 1)); axis(ax, 'xy');
colormap(ax, parula); cb = colorbar(ax); cb.Label.String = '20 log_{10}(|code| + 1)  (dB)';
set(ax, 'FontName', FONT, 'FontSize', FS, 'TickDir', 'out'); cb.FontName = FONT; cb.FontSize = FS;
xlabel(ax, 'ramp (transmitter-interleaved order)'); ylabel(ax, 'range bin');
exportgraphics(f, fullfile(outDir, 'fig_input_report.png'), 'Resolution', 300, 'BackgroundColor', 'white');
close(f);
fprintf('thesis_figs_results: wrote 7 figures to %s\n', outDir);
