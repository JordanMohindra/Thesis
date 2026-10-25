%% make_poster_figs.m - figures and tables for the A3 thesis poster
%
%  Everything here is computed from the simulation code in this folder:
%    Stage 1  run_coloradar_benchmark  -> all 8 algorithms (runCompressionSim)
%    Stage 2  compress_drhe / compress_lpc_huffman on the FPGA test set
%             (4 RX): how much of the compression comes from the Huffman
%             coder and how much from the prediction
%    Hardware Vivado reports and board results in ../fpga_kcu116
%
%  Change the PARAMETERS below and run again. Simulation results are cached
%  in <outDir>/poster_results.mat and only recomputed when the parameters
%  that affect them change (or when P.recompute = true). The cache does not
%  notice edits to the algorithm code itself: set P.recompute = true then.
%
%  Outputs (in P.outDir): fig_stage1.png, fig_cr_bars.png, fig_cr_frames.png,
%  fig_timing.png, fig_resources.png, fig_input.png, fig_residual.png, and the numbers behind the poster
%  tables: poster_stage1.csv, poster_stage2.csv, poster_hardware.csv.

clear; close all;
here = fileparts(mfilename('fullpath'));
repo = fileparts(here);                                  % ...\ThesisA

%% ======================= PARAMETERS =====================================
P.dataDir       = '';          % ColoRadar frames ('' = find_coloradar_data)

% Stage 1: screen every algorithm (full pipeline incl. detection metrics)
P.stage1Frames  = 50;          % frames to average over
P.stage1TX      = 1:12;        % transmitters kept by the loader
P.stage1PredLag = [];          % DRHE/LPC lag: [] = per transmitter (nTx),
                               %               1  = old consecutive-ramp predictor

% Stage 2: DRHE vs LPC on the FPGA test set
P.stage2Frames  = 50;
P.stage2Rx      = 1:4;         % RX channels (the FPGA test uses 4)
P.stage2PredLag = [];          % [] = nTx (12)
P.dictMode      = 'thesis';    % re-derived dictionary for the per-frame plot:
                               % 'thesis': tables in huffman_tables.m (= FPGA cores)
                               % 'train' : retrain from P.trainFrames below
P.trainFrames   = 0:4;         % training frames ('train' mode retrains on these;
                               %  the 'thesis' tables were trained on 0:4)
P.pseudoCount   = 1;           % added to every S4 count when training

% Hardware results
P.fpgaDir       = fullfile(repo, 'fpga_kcu116');
P.clockHz       = 100e6;       % FPGA clock

P.recompute     = false;       % true = ignore the cache and rerun everything
P.outDir        = fullfile(repo, 'poster');
P.figWidth      = 3.4;         % inches (figure layout; scale up freely on the poster)
P.dpi           = 600;         % PNG resolution: 3.4 in at 600 dpi stays sharp at ~7 in wide on A0
P.inputFrame    = 0;           % frame and RX shown in fig_input
P.inputRx       = 1;
%% ========================================================================

if ~exist(P.outDir, 'dir'), mkdir(P.outDir); end
cacheFile = fullfile(P.outDir, 'poster_results.mat');
cache = struct();
if exist(cacheFile, 'file') && ~P.recompute, cache = load(cacheFile); end

%% ---- Stage 1: all algorithms -------------------------------------------
s1key = struct('frames', P.stage1Frames, 'tx', P.stage1TX, 'lag', P.stage1PredLag, 'dataDir', P.dataDir);
if isfield(cache, 'stage1') && isequal(cache.stage1.key, s1key)
    stage1 = cache.stage1;
    fprintf('Stage 1: using cached results (%d frames)\n', P.stage1Frames);
else
    fprintf('Stage 1: running the benchmark on %d frames (slow)...\n', P.stage1Frames);
    t0 = tic;
    [stage1.T, stage1.perFrame] = run_coloradar_benchmark(struct('nFrames', P.stage1Frames, ...
        'dataDir', P.dataDir, 'txSelect', P.stage1TX, 'predLag', P.stage1PredLag));
    stage1.key = s1key;
    fprintf('Stage 1: done in %.1f min\n', toc(t0) / 60);
    cache.stage1 = stage1; save(cacheFile, '-struct', 'cache');
end
disp(stage1.T);
writetable(stage1.T, fullfile(P.outDir, 'poster_stage1.csv'));

%% ---- Stage 2: DRHE vs LPC (S4 histograms per frame) --------------------
% For each frame the residuals of each method are reduced to a histogram of
% S4 values. The bit count for any dictionary is then sum(hist .* (L + S4)),
% so dictionaries can be trained and compared without recompressing.
s2key = struct('frames', P.stage2Frames, 'rx', P.stage2Rx, 'lag', P.stage2PredLag, 'dataDir', P.dataDir);
if isfield(cache, 'stage2') && isequal(cache.stage2.key, s2key)
    stage2 = cache.stage2;
    fprintf('Stage 2: using cached results (%d frames)\n', P.stage2Frames);
else
    stage2 = run_stage2(P);
    stage2.key = s2key;
    cache.stage2 = stage2; save(cacheFile, '-struct', 'cache');
end

kiem = huffman_tables('kiem');
switch P.dictMode
    case 'thesis'
        dictD = huffman_tables('drhe_retrained');
        dictL = huffman_tables('lpc_retrained');
    case 'train'
        tr = ismember(stage2.frame, P.trainFrames);
        dictD = huffman_code_lengths(sum(stage2.histDRHE(tr, :), 1), P.pseudoCount);
        dictL = huffman_code_lengths(sum(stage2.histLPC(tr, :), 1), P.pseudoCount);
    otherwise
        error('P.dictMode must be ''thesis'' or ''train''');
end
fprintf('Re-derived dictionaries (%s):\n  DRHE %s\n  LPC  %s\n', P.dictMode, mat2str(dictD), mat2str(dictL));

crOf = @(hist, dict, extra) stage2.inputBits ./ (hist * (dict + (0:15))' + extra);
cr.none     = crOf(stage2.histNone, kiem,  0);       % Huffman coder alone, no prediction
cr.drheKiem = crOf(stage2.histDRHE, kiem,  0);       % prediction + Huffman coder
cr.lpcKiem  = crOf(stage2.histLPC,  kiem,  stage2.lpcOverhead);
cr.drheNew  = crOf(stage2.histDRHE, dictD, 0);
cr.lpcNew   = crOf(stage2.histLPC,  dictL, stage2.lpcOverhead);
heldOut = ~ismember(stage2.frame, P.trainFrames);

% Where the compression comes from, step by step:
%   Huffman coder alone on the raw values (Kiem's dictionary) -> cr.none
%   + prediction (code the residual instead)                   -> cr.<algo>Kiem
%   + the re-derived dictionary (the one in the FPGA cores)     -> cr.<algo>New
% The three steps add up to the total.
S2 = table({'DRHE'; 'LPC'}, ...
    [mean(cr.none); mean(cr.none)], ...
    [mean(cr.drheKiem) - mean(cr.none); mean(cr.lpcKiem) - mean(cr.none)], ...
    [mean(cr.drheNew) - mean(cr.drheKiem); mean(cr.lpcNew) - mean(cr.lpcKiem)], ...
    [mean(cr.drheNew); mean(cr.lpcNew)], ...
    [mean(cr.drheNew(heldOut)); mean(cr.lpcNew(heldOut))], ...
    'VariableNames', {'Algorithm', 'CR_HuffmanOnly', 'CR_AddedByPrediction', 'CR_AddedByDictionary', ...
                      'CR_Total', 'CR_Total_HeldOut'});
disp(S2);
writetable(S2, fullfile(P.outDir, 'poster_stage2.csv'));

%% ---- Hardware: Vivado reports and board results -------------------------
hw = read_hardware(P);
H = table({'DRHE'; 'LPC'}, ...
    [hw.drhe.enc_cycles; hw.lpc.enc_cycles], [hw.drhe.enc_latency; hw.lpc.enc_latency], [hw.drhe.gibps; hw.lpc.gibps], ...
    [hw.drhe.dec_cycles; hw.lpc.dec_cycles], [hw.drhe.dec_latency; hw.lpc.dec_latency], ...
    [hw.drhe.res_enc; hw.lpc.res_enc], [hw.drhe.res_dec; hw.lpc.res_dec], ...
    'VariableNames', {'Algorithm', 'EncCyclesPerFrame', 'EncLatencyCycles', 'EncThroughput_Gibps', ...
                      'DecCyclesPerFrame', 'DecLatencyCycles', 'Encoder_LUT_FF_BRAM_DSP', 'Decoder_LUT_FF_BRAM_DSP'});
disp(H); fprintf('  encoder timing from: %s\n  decoder timing from: %s\n', hw.encSource, hw.decSource);
writetable(H, fullfile(P.outDir, 'poster_hardware.csv'));

%% ======================= FIGURES =========================================
W = P.figWidth;
set(groot, 'defaultAxesFontSize', 9, 'defaultTextFontSize', 8);
C = colororder; grey = [0.65 0.65 0.65];
setappdata(groot, 'posterDPI', P.dpi);

% ---- Stage 1: CR vs missed detections ----
T1 = stage1.T;
lbl = containers.Map({'FP16', 'DRHEfp16', 'FX16', 'DRHE', 'BAQ', 'RDVLE', 'RDVLE_UDRE', 'LPC_Huffman'}, ...
                     {'FP16 / DRHE fp16 (float)', '', 'FX16 baseline', 'DRHE', 'BAQ', 'RDVLE', 'RDVLE UDRE', 'LPC'});
grp = containers.Map({'FP16', 'DRHEfp16', 'FX16', 'DRHE', 'BAQ', 'RDVLE', 'RDVLE_UDRE', 'LPC_Huffman'}, {1, 1, 1, 2, 3, 3, 3, 2});
fx16FN = T1.FN_pct(strcmp(T1.Algorithm, 'FX16'));
f = newfig(W, 2.5);
xr = [0.8, max(T1.CR) + 0.6]; yr = [-2, max(T1.FN_pct) * 1.15];
selX = min(T1.CR(strcmp(T1.Algorithm, 'DRHE') | strcmp(T1.Algorithm, 'LPC_Huffman'))) - 0.4;
rectangle('Position', [selX, yr(1), xr(2) - selX, fx16FN + 1.7 - yr(1)], 'FaceColor', [0.89 0.94 0.85], 'EdgeColor', 'none'); hold on
text(xr(2) - 0.05, 0, 'selected', 'HorizontalAlignment', 'right', 'Color', [0.18 0.49 0.20]);
cols = {grey, C(1,:), C(2,:)}; h = gobjects(1, 3);
for i = 1:height(T1)
    g = grp(T1.Algorithm{i});
    h(g) = plot(T1.CR(i), T1.FN_pct(i), 'o', 'MarkerSize', 6, 'MarkerFaceColor', cols{g}, 'MarkerEdgeColor', 'k');
    if any(strcmp(T1.Algorithm{i}, {'DRHE', 'RDVLE_UDRE'}))   % label on the left of the point
        text(T1.CR(i) - 0.07, T1.FN_pct(i) + 0.05 * diff(yr), lbl(T1.Algorithm{i}), 'FontSize', 7, 'HorizontalAlignment', 'right');
    else
        text(T1.CR(i) + 0.07, T1.FN_pct(i) + 0.012 * diff(yr) * (1 + 3 * (g == 2)), lbl(T1.Algorithm{i}), 'FontSize', 7);
    end
end
xlim(xr); ylim(yr); grid on; box on
xlabel('Compression ratio  \rightarrow  better'); ylabel('Missed detections, FN (%)')
title(sprintf('Stage 1: all algorithms (%d frames)', P.stage1Frames))

save_fig(f, P.outDir, 'fig_stage1.png');

% ---- Stage 2: where the compression comes from (waterfall) ----
% For each algorithm: the Huffman coder alone, the extra from predicting,
% the extra from the re-derived dictionary, and the total they add up to.
f = newfig(W, 2.35);
xs = [1 2 3 4; 6 7 8 9];                                 % DRHE group, LPC group
dark = [0.30 0.30 0.30]; green = [0.47 0.67 0.19];
for a = 1:2
    base = S2.CR_HuffmanOnly(a); p = S2.CR_AddedByPrediction(a); d = S2.CR_AddedByDictionary(a); tot = S2.CR_Total(a);
    bar(xs(a, 1), base, 0.7, 'FaceColor', C(1,:)); hold on
    bm = bar(xs(a, 2), [base p], 0.7, 'stacked');         % floating bars
    bm(1).FaceColor = 'none'; bm(1).EdgeColor = 'none'; bm(2).FaceColor = C(2,:);
    bm = bar(xs(a, 3), [base + p, d], 0.7, 'stacked');
    bm(1).FaceColor = 'none'; bm(1).EdgeColor = 'none'; bm(2).FaceColor = green;
    bar(xs(a, 4), tot, 0.7, 'FaceColor', dark);
    plot([xs(a, 1) + 0.35, xs(a, 2) - 0.35], [base base], 'k:', 'LineWidth', 0.8);
    plot([xs(a, 2) + 0.35, xs(a, 3) - 0.35], [base + p, base + p], 'k:', 'LineWidth', 0.8);
    plot([xs(a, 3) + 0.35, xs(a, 4) - 0.35], [tot tot], 'k:', 'LineWidth', 0.8);
    text(xs(a, 1), base + 0.08, sprintf('%.2f', base), 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', 7);
    text(xs(a, 2), base + p + 0.08, sprintf('+%.2f', p), 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', 7);
    text(xs(a, 3), tot + 0.08, sprintf('+%.2f', d), 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', 7);
    text(xs(a, 4), tot + 0.08, sprintf('%.2f', tot), 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', 7.5, 'FontWeight', 'bold');
end
xlim([0.3 9.7]); ylim([0, ceil(max(S2.CR_Total)) + 2]); grid on; box on
set(gca, 'XTick', [2.5 7.5], 'XTickLabel', {'DRHE', 'LPC'});
lg = gobjects(1, 4); cl = {C(1,:), C(2,:), green, dark};
for i = 1:4, lg(i) = patch(NaN, NaN, cl{i}); end
legend(lg, {'Huffman coder', '+ prediction', '+ new dictionary', 'Total'}, 'Location', 'north', 'NumColumns', 2, 'FontSize', 7)
ylabel('Compression ratio'); title('Stage 2: where the CR comes from')
save_fig(f, P.outDir, 'fig_cr_bars.png');

% ---- Per-frame CR, re-derived dictionary ----
f = newfig(W, 1.85);
fr = stage2.frame;
p1 = plot(fr, cr.drheNew, '-o', 'MarkerSize', 2.5, 'LineWidth', 1.2, 'Color', C(1,:), 'MarkerFaceColor', C(1,:)); hold on
p2 = plot(fr, cr.lpcNew,  '-s', 'MarkerSize', 2.5, 'LineWidth', 1.2, 'Color', C(2,:), 'MarkerFaceColor', C(2,:));
xlim([min(fr) - 0.5, max(fr) + 0.5]); ylim([0, ceil(max([cr.drheNew; cr.lpcNew])) + 1]); grid on; box on
xlabel('Frame'); ylabel('Compression ratio'); title('Per-frame CR, re-derived dictionary')
legend([p1 p2], {'DRHE', 'LPC'}, 'Location', 'south', 'NumColumns', 2)
save_fig(f, P.outDir, 'fig_cr_frames.png');

% ---- Encode / decode time per frame (linear time axis) ----
% One row per operation; the bar is the time to process one whole frame.
% The latency bracket is the measured time from the last input word read
% to the last output word written. DRHE outputs as it goes, so its
% latency is tiny; LPC can only start emitting once it has the whole frame.
ms = @(cyc) cyc / P.clockHz * 1e3;
rows = {'DRHE encode', 'DRHE decode', 'LPC encode', 'LPC decode'};
f = newfig(W, 2.3); hold on
yTop = 4; hgt = 0.6;
enc = {hw.drhe, hw.lpc};
for a = 1:2
    y = yTop - 2 * (a - 1); e = enc{a}; tE = e.enc_cycles;
    barh_seg(y, 0, ms(tE), C(a,:), hgt);
    if ms(e.enc_latency) <= 0.05                      % too short to draw: no bracket
        text(ms(tE) + 0.05, y, sprintf('%.2f ms', ms(tE)), 'FontSize', 7);
    else                                              % draw the latency as a bracket
        text(ms(tE) + 0.05, y, sprintf('%.2f ms', ms(tE)), 'FontSize', 7);
        lat0 = ms(tE - e.enc_latency);
        plot([lat0 ms(tE)], [y + 0.5 y + 0.5], 'k-', 'LineWidth', 0.8); plot([lat0 lat0], [y + 0.4 y + 0.6], 'k-'); plot(ms([tE tE]), [y + 0.4 y + 0.6], 'k-');
        text((lat0 + ms(tE)) / 2, y + 0.72, ['latency ' fmt_time(e.enc_latency, P.clockHz)], 'HorizontalAlignment', 'center', 'FontSize', 7);
    end
end
% decoders (on-chip, from the *_full bitstreams)
for a = {'drhe', 'lpc'}
    y = yTop - 1 - 2 * strcmp(a{1}, 'lpc'); d = hw.(a{1});
    if isnan(d.dec_cycles)
        text(0.05, y, 'decode: run run\_board.bat ' + string(a{1}) + '\_full', 'FontSize', 7, 'FontAngle', 'italic', 'Color', [0.4 0.4 0.4]);
    else
        barh_seg(y, 0, ms(d.dec_cycles), (C(1 + strcmp(a{1}, 'lpc'), :) + 1) / 2, hgt);
        txt = sprintf('%.2f ms', ms(d.dec_cycles));
        if ~isnan(d.dec_latency), txt = [txt ', latency ' fmt_time(d.dec_latency, P.clockHz)]; end %#ok<AGROW>
        text(ms(d.dec_cycles) + 0.05, y, txt, 'FontSize', 7);
    end
end
set(gca, 'YTick', yTop - (3:-1:0), 'YTickLabel', fliplr(rows)); ylim([yTop - 3.6, yTop + 0.9])
xl = xlim; xlim([0, max([xl(2), ms(hw.lpc.enc_cycles) * 1.5])]); grid on; box on
xlabel('Time per frame (ms, 100 MHz)'); title('Encode and decode time per frame')
save_fig(f, P.outDir, 'fig_timing.png');

% ---- FPGA resources: encoder, decoder, both (cores only) ----
f = newfig(W, 2.3);
tl = tiledlayout(f, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
algs = {'drhe', 'lpc'}; names = {'DRHE', 'LPC'};
chip = [216960, 433920, 480, 1824];                       % XCKU5P: LUT, FF, BRAM36, DSP
U = cell(1, 2);
for a = 1:2
    e = hw.(algs{a}).res_enc ./ chip; d = hw.(algs{a}).res_dec ./ chip;
    U{a} = 100 * [e([1 3 4]); d([1 3 4]); e([1 3 4]) + d([1 3 4])];   % rows: enc, dec, both
end
ymax = 10 * ceil(max([U{:}], [], 'all') / 10 + 0.3);
for a = 1:2
    nexttile(tl);
    b = bar(U{a}, 0.85); grid on; box on; ylim([0 ymax])
    set(gca, 'XTickLabel', {'Enc', 'Dec', 'Both'})
    title(names{a}); if a == 1, ylabel('% of XCKU5P'); end
    if a == 2
        lg = legend(b, {'LUT', 'BRAM', 'DSP'}, 'Orientation', 'horizontal', 'FontSize', 7);
        lg.Layout.Tile = 'south';
    end
end
title(tl, 'FPGA resources: encoder, decoder, both', 'FontSize', 10, 'FontWeight', 'bold');
save_fig(f, P.outDir, 'fig_resources.png');

% ---- Input data: one range-FFT frame (what the compressor receives) ----
[dataDir, frameFiles] = find_coloradar_data(P.dataDir);
fi = find(arrayfun(@(d) sscanf(d.name, 'frame_%d.bin'), frameFiles) == P.inputFrame, 1);
binFile = fullfile(dataDir, frameFiles(fi).name);
loadOpts = struct('txSelect', 1:12, 'removeDC', true, 'fx16EffectiveBits', 16);
[~, cube, config] = evalc('loadColoRadarFrame(binFile, loadOpts)');
fx = compress_fx16(rangeFFT(preprocessing(cube, config), config), config);
X = complex(double(fx.real_part(:, :, P.inputRx)), double(fx.imag_part(:, :, P.inputRx)));
f = newfig(W, 2.5);
imagesc(0:size(X, 2) - 1, 0:size(X, 1) - 1, 20 * log10(abs(X) + 1)); axis xy
colormap(gca, parula); cb = colorbar; cb.Label.String = 'Magnitude (dB)';
xlabel('Ramp (chirp loop \times TX)'); ylabel('Range bin');
title(sprintf('Input: frame %d, RX %d (int16 I/Q)', P.inputFrame, P.inputRx))
save_fig(f, P.outDir, 'fig_input.png');

% ---- Why prediction helps: how many bits each value needs ----
% S4 = number of magnitude bits a value needs (0 for zero). Small S4 means
% a short Huffman code plus few APPEND bits.
hN = sum(stage2.histNone, 1); hD = sum(stage2.histDRHE, 1); hL = sum(stage2.histLPC, 1);
pct = 100 * [hN / sum(hN); hD / sum(hD); hL / sum(hL)]';
kmax = find(any(pct > 0.5, 2), 1, 'last');
f = newfig(W, 2.3);
b = bar(0:kmax - 1, pct(1:kmax, :), 0.9);
b(1).FaceColor = grey; b(2).FaceColor = C(1,:); b(3).FaceColor = C(2,:);
grid on; box on; xlim([-0.6, kmax - 0.4])
xlabel('Bits needed for the value (S4)'); ylabel('% of values')
title('Prediction makes the values smaller')
legend({'raw sample', 'DRHE residual', 'LPC residual'}, 'Location', 'northeast')
save_fig(f, P.outDir, 'fig_residual.png');

fprintf('\nPoster figures and tables written to %s\n', P.outDir);

%% ======================= LOCAL FUNCTIONS =================================
function stage2 = run_stage2(P)
    [dataDir, frameFiles] = find_coloradar_data(P.dataDir);
    n = min(P.stage2Frames, numel(frameFiles));
    stage2.frame = zeros(n, 1);
    stage2.histNone = zeros(n, 16); stage2.histDRHE = zeros(n, 16); stage2.histLPC = zeros(n, 16);
    stage2.lpcOverhead = zeros(n, 1); stage2.inputBits = zeros(n, 1);
    edges = -0.5:1:15.5;
    loadOpts = struct('txSelect', 1:12, 'removeDC', true, 'fx16EffectiveBits', 16);
    fprintf('Stage 2: DRHE and LPC on %d frames, RX %s...\n', n, mat2str(P.stage2Rx));
    t0 = tic;
    for k = 1:n
        binFile = fullfile(dataDir, frameFiles(k).name);
        [~, cube, config] = evalc('loadColoRadarFrame(binFile, loadOpts)');
        fx = compress_fx16(rangeFFT(preprocessing(cube, config), config), config);
        fx.real_part = fx.real_part(:, :, P.stage2Rx);
        fx.imag_part = fx.imag_part(:, :, P.stage2Rx);
        config.numRxChannels = numel(P.stage2Rx);
        if ~isempty(P.stage2PredLag), config.predLag = P.stage2PredLag; end

        cD = compress_drhe(fx, config);
        cL = compress_lpc_huffman(fx, config);

        stage2.frame(k)       = sscanf(frameFiles(k).name, 'frame_%d.bin');
        stage2.histNone(k, :) = histcounts(s4_region([fx.real_part(:); fx.imag_part(:)]), edges);
        stage2.histDRHE(k, :) = histcounts(s4_region([cD.diffReal(:); cD.diffImag(:)]), edges);
        stage2.histLPC(k, :)  = histcounts(s4_region([cL.diffReal(:); cL.diffImag(:)]), edges);
        stage2.lpcOverhead(k) = cL.overheadBits;
        stage2.inputBits(k)   = cD.inputBits;
        fprintf('  stage 2: %s  DRHE %.3f  LPC %.3f (Kiem dictionary)\n', frameFiles(k).name, cD.CR, cL.CR);
    end
    fprintf('Stage 2: done in %.1f min\n', toc(t0) / 60);
end

function hw = read_hardware(P)
% Encoder timing: board results/<algo>/results.bin, else the board-run
% summary in reports/. Decoder timing: results/<algo>_full/results.bin
% (bitstreams with the on-chip decompressor), NaN until that board run.
% Resources: per-core rows of the hierarchical Vivado reports of the
% *_full builds (compressor 'comp' and decompressor 'decomp').
    fpgaDir = P.fpgaDir;
    hw.encSource = ''; hw.decSource = '';
    for a = {'drhe', 'lpc'}
        r = read_results(fullfile(fpgaDir, 'results', a{1}));
        if ~isempty(r)
            hw.(a{1}).enc_cycles = mean(r(3, :)); hw.(a{1}).enc_latency = mean(r(8, :));
            hw.encSource = [hw.encSource ' results/' a{1}];
        else
            txt = fileread(fullfile(fpgaDir, 'reports', 'fpga_results_summary_kiem_dictionary.txt'));
            c = summary_pair(txt, 'Clock cycles per frame');
            l = summary_pair(txt, 'End-to-end latency');            % in us
            col = 1 + strcmp(a{1}, 'lpc');
            hw.(a{1}).enc_cycles = c(col); hw.(a{1}).enc_latency = l(col) * P.clockHz / 1e6;
            hw.encSource = 'reports/fpga_results_summary_kiem_dictionary.txt';
        end
        frameBits = 128 * 192 * 4 * 2 * 16;
        hw.(a{1}).gibps = frameBits / (hw.(a{1}).enc_cycles / P.clockHz) / 2^30;

        r = read_results(fullfile(fpgaDir, 'results', [a{1} '_full']));
        hw.(a{1}).dec_cycles = NaN; hw.(a{1}).dec_latency = NaN;
        if ~isempty(r)
            hw.(a{1}).dec_cycles = mean(r(4, :));
            if size(r, 1) >= 9, hw.(a{1}).dec_latency = mean(r(9, :)); end
            hw.decSource = [hw.decSource ' results/' a{1} '_full'];
        end

        rpt = first_existing({fullfile(fpgaDir, 'out', ['kcu116_' a{1} '_full_util_hier.rpt']), ...
                              fullfile(fpgaDir, 'reports', ['kcu116_' a{1} '_full_util_hier.rpt'])});
        txt = fileread(rpt);
        hw.(a{1}).res_enc = hier_row(txt, 'comp');
        hw.(a{1}).res_dec = hier_row(txt, 'decomp');
    end
    if isempty(hw.decSource), hw.decSource = 'none yet (run the *_full bitstreams on the board)'; end
end

function r = read_results(rdir)
% results.bin from run_board.tcl: one record per frame, 8 words (older
% firmware) or 16 words (fw 1.1, adds the decoder latency as word 9).
    r = [];
    rb = fullfile(rdir, 'results.bin');
    if ~exist(rb, 'file'), return; end
    words = 8;
    ri = fullfile(rdir, 'run_info.txt');
    if exist(ri, 'file')
        tok = regexp(fileread(ri), 'rec_words (\d+)', 'tokens', 'once');
        if ~isempty(tok), words = str2double(tok{1}); end
    end
    fid = fopen(rb); r = fread(fid, [words inf], 'uint32=>double'); fclose(fid);
end

function v = hier_row(txt, inst)
% [LUT FF BRAM36 DSP] of one instance in a report_utilization -hierarchical file
    line = regexp(txt, ['\|\s+' inst '\s+\|[^\n]*'], 'match', 'once');
    c = str2double(strtrim(split(line, '|')));
    c = c(~isnan(c));            % Total LUTs, Logic LUTs, LUTRAMs, SRLs, FFs, RAMB36, RAMB18, URAM, DSP
    v = [c(1), c(5), c(6) + c(7) / 2, c(9)];
end

function v = summary_pair(txt, label)
    line = regexp(txt, [label '[^\n]*'], 'match', 'once');
    nums = regexp(strrep(line(numel(label) + 1:end), ',', ''), '[\d.]+', 'match');
    v = str2double(nums(1:2));
end

function p = first_existing(list)
    for i = 1:numel(list)
        if exist(list{i}, 'file'), p = list{i}; return; end
    end
    error('none of these files exist: %s', strjoin(list, ', '));
end

function barh_seg(y, x0, x1, col, hgt)
    rectangle('Position', [x0, y - hgt / 2, max(x1 - x0, 1e-3), hgt], 'FaceColor', col, 'EdgeColor', 'k', 'LineWidth', 0.5);
end

function s = fmt_time(cycles, clk)
    t = cycles / clk;
    if t >= 1e-3, s = sprintf('%.2f ms', t * 1e3); else, s = sprintf('%.1f \\mus', t * 1e6); end
end

function f = newfig(w, h)
    f = figure('Units', 'inches', 'Position', [1 1 w h], 'Color', 'w', 'Visible', 'off');
end

function save_fig(f, outdir, name)
    dpi = getappdata(groot, 'posterDPI'); if isempty(dpi), dpi = 300; end
    target = fullfile(outdir, name);
    try
        exportgraphics(f, target, 'Resolution', dpi, 'BackgroundColor', 'white');
    catch
        % the PNG is open in another program (e.g. Photos): save beside it
        alt = strrep(target, '.png', '_new.png');
        exportgraphics(f, alt, 'Resolution', dpi, 'BackgroundColor', 'white');
        warning('%s is open in another program; saved %s instead', name, alt);
    end
    close(f);
end
