%% make_poster_figs.m - figures and tables for the A3 thesis poster
%
%  Everything here is computed from the simulation code in this folder:
%    Stage 1  run_coloradar_benchmark  -> all 8 algorithms (runCompressionSim)
%    Stage 2  compress_drhe / compress_lpc_huffman on the FPGA test set
%             (4 RX), with Kiem's and the re-derived Huffman dictionaries
%    Hardware Vivado reports and board results in ../fpga_kcu116
%
%  Change the PARAMETERS below and run again. Simulation results are cached
%  in <outDir>/poster_results.mat and only recomputed when the parameters
%  that affect them change (or when P.recompute = true).
%
%  Outputs (in P.outDir): fig_stage1.png, fig_cr_bars.png, fig_cr_frames.png,
%  fig_latency.png, fig_resources.png, and the numbers behind the poster
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
P.dictMode      = 'thesis';    % 'thesis': tables in huffman_tables.m (= FPGA cores)
                               % 'train' : retrain from P.trainFrames below
P.trainFrames   = 0:4;         % training frames ('train' mode retrains on these;
                               %  the 'thesis' tables were trained on 0:4)
P.pseudoCount   = 1;           % added to every S4 count when training

% Hardware results
P.fpgaDir       = fullfile(repo, 'fpga_kcu116');

P.recompute     = false;       % true = ignore the cache and rerun everything
P.outDir        = fullfile(repo, 'poster');
P.figWidth      = 3.4;         % inches: one poster column
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
cr.none     = crOf(stage2.histNone, kiem,  0);
cr.drheKiem = crOf(stage2.histDRHE, kiem,  0);
cr.lpcKiem  = crOf(stage2.histLPC,  kiem,  stage2.lpcOverhead);
cr.drheNew  = crOf(stage2.histDRHE, dictD, 0);
cr.lpcNew   = crOf(stage2.histLPC,  dictL, stage2.lpcOverhead);
heldOut = ~ismember(stage2.frame, P.trainFrames);

S2 = table({'No prediction'; 'DRHE'; 'LPC'}, ...
    [mean(cr.none); mean(cr.drheKiem); mean(cr.lpcKiem)], ...
    [NaN; mean(cr.drheNew); mean(cr.lpcNew)], ...
    [NaN; mean(cr.drheNew(heldOut)); mean(cr.lpcNew(heldOut))], ...
    'VariableNames', {'Method', 'CR_KiemDict', 'CR_RederivedDict', 'CR_Rederived_HeldOut'});
disp(S2);
writetable(S2, fullfile(P.outDir, 'poster_stage2.csv'));

%% ---- Hardware: Vivado reports and board results -------------------------
hw = read_hardware(P.fpgaDir);
H = table({'DRHE'; 'LPC'}, [hw.drhe.cycles; hw.lpc.cycles], [hw.drhe.gibps; hw.lpc.gibps], ...
    [hw.drhe.latency_us; hw.lpc.latency_us], [hw.drhe.util; hw.lpc.util], [hw.drhe_full.util; hw.lpc_full.util], ...
    'VariableNames', {'Algorithm', 'CyclesPerFrame', 'Throughput_Gibps', 'Latency_us', ...
                      'Util_CompOnly_LUT_BRAM_DSP', 'Util_WithDecomp_LUT_BRAM_DSP'});
disp(H); fprintf('  (board results from: %s)\n', hw.source);
writetable(H, fullfile(P.outDir, 'poster_hardware.csv'));

% Reference values from Kiem's thesis (ZU3CG, Infineon CTRX), quoted, not simulated
K.latency_us = 79.4;      % end-to-end incl. range FFT
K.gibps      = 11.92;     % calculated input throughput
K.crHW       = 3.17;      % lossless CR on hardware

%% ======================= FIGURES =========================================
W = P.figWidth;
set(groot, 'defaultAxesFontSize', 9, 'defaultTextFontSize', 8);
C = colororder; grey = [0.65 0.65 0.65];

% ---- Stage 1: CR vs missed detections ----
T1 = stage1.T;
lbl = containers.Map({'FP16', 'DRHEfp16', 'FX16', 'DRHE', 'BAQ', 'RDVLE', 'RDVLE_UDRE', 'LPC_Huffman'}, ...
                     {'FP16 / DRHE fp16 (float)', '', 'FX16 baseline', 'DRHE', 'BAQ', 'RDVLE', 'RDVLE UDRE', 'LPC'});
grp = containers.Map({'FP16', 'DRHEfp16', 'FX16', 'DRHE', 'BAQ', 'RDVLE', 'RDVLE_UDRE', 'LPC_Huffman'}, {1, 1, 1, 2, 3, 3, 3, 2});
fx16FN = T1.FN_pct(strcmp(T1.Algorithm, 'FX16'));
f = newfig(W, 2.5);
xr = [0.8, max(T1.CR) + 0.6]; yr = [-2, max(T1.FN_pct) * 1.4];          % headroom for the legend
goalX = min(T1.CR(strcmp(T1.Algorithm, 'DRHE') | strcmp(T1.Algorithm, 'LPC_Huffman'))) - 0.4;
rectangle('Position', [goalX, yr(1), xr(2) - goalX, fx16FN + 1.7 - yr(1)], 'FaceColor', [0.89 0.94 0.85], 'EdgeColor', 'none'); hold on
text(xr(2) - 0.05, 0, 'goal', 'HorizontalAlignment', 'right', 'Color', [0.18 0.49 0.20]);
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
legend(h, {'reference', 'lossless', 'lossy'}, 'Location', 'northeast')
save_fig(f, P.outDir, 'fig_stage1.png');

% ---- Stage 2: mean CR, two dictionaries ----
y = [S2.CR_KiemDict, S2.CR_RederivedDict];
f = newfig(W, 2.35);
b = bar(y, 0.8); hold on
b(1).FaceColor = 'flat'; b(1).CData(1, :) = grey;
for s = 1:2
    for i = 1:3
        if ~isnan(y(i, s))
            text(b(s).XEndPoints(i), y(i, s) + 0.08, sprintf('%.2f', y(i, s)), 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', 7.5);
        end
    end
end
xticklabels(S2.Method); ylim([0 ceil(max(y(:)) + 1.5)]); grid on; box on
ylabel('Compression ratio'); title(sprintf('Stage 2: DRHE vs LPC, mean CR (%d frames)', P.stage2Frames))
lg1 = patch(NaN, NaN, C(1,:)); lg2 = patch(NaN, NaN, C(2,:));
legend([lg1 lg2], {'Kiem''s dictionary', 'Re-derived dictionary'}, 'Location', 'north', 'NumColumns', 2)
save_fig(f, P.outDir, 'fig_cr_bars.png');

% ---- Per-frame CR, re-derived dictionary ----
f = newfig(W, 1.85);
fr = stage2.frame; yl = [floor(min([cr.drheNew; cr.lpcNew]) * 10) / 10 - 0.2, ceil(max([cr.drheNew; cr.lpcNew]) * 10) / 10 + 0.5];
tf = P.trainFrames;          % shade the frames the dictionary was trained on
patch([min(tf) - 0.5, max(tf) + 0.5, max(tf) + 0.5, min(tf) - 0.5], yl([1 1 2 2]), [0.85 0.85 0.85], 'EdgeColor', 'none', 'FaceAlpha', 0.6); hold on
text(mean(tf), yl(1) + 0.08, 'train', 'HorizontalAlignment', 'center', 'FontSize', 7, 'Color', [0.25 0.25 0.25]);
p1 = plot(fr, cr.drheNew, '-o', 'MarkerSize', 2.5, 'LineWidth', 1.2, 'Color', C(1,:), 'MarkerFaceColor', C(1,:)); hold on
p2 = plot(fr, cr.lpcNew,  '-s', 'MarkerSize', 2.5, 'LineWidth', 1.2, 'Color', C(2,:), 'MarkerFaceColor', C(2,:));
xlim([min(fr) - 0.5, max(fr) + 0.5]); ylim(yl); grid on; box on
xlabel('Frame'); ylabel('Compression ratio'); title('Per-frame CR, re-derived dictionary')
legend([p1 p2], {'DRHE', 'LPC'}, 'Location', 'north', 'NumColumns', 2)
save_fig(f, P.outDir, 'fig_cr_frames.png');

% ---- Latency (log scale) ----
lat = [hw.drhe.latency_us, K.latency_us, hw.lpc.latency_us];
f = newfig(W * 0.92, 2.2);
b = bar(lat, 0.6); b.FaceColor = 'flat'; b.CData = [C(1,:); grey; C(2,:)]; hold on
set(gca, 'YScale', 'log', 'YMinorGrid', 'off', 'YMinorTick', 'off'); ylim([1, 10^ceil(log10(max(lat)) + 0.3)]); grid on; box on
for i = 1:3
    text(i, lat(i) * 1.3, [fmt_num(lat(i)) ' \mus'], 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', 7.5);
end
xticklabels({'DRHE', 'Kiem [1]', 'LPC'}); ylabel('Latency (\mus)'); title('End-to-end latency')
save_fig(f, P.outDir, 'fig_latency.png');

% ---- FPGA resources ----
U = 100 * [hw.drhe.util; hw.lpc.util; hw.drhe_full.util; hw.lpc_full.util];
f = newfig(W, 2.3);
b = bar(U, 0.85); ylim([0, 10 * ceil(max(U(:)) / 10 + 0.5)]); grid on; box on
xticklabels({'DRHE', 'LPC', 'DRHE\newline+ decomp', 'LPC\newline+ decomp'}); xtickangle(0); ylabel('% of XCKU5P')
title('FPGA resources (whole system)')
legend(b, {'LUT', 'BRAM', 'DSP'}, 'Location', 'northwest', 'NumColumns', 3)
save_fig(f, P.outDir, 'fig_resources.png');

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

function hw = read_hardware(fpgaDir)
% Resources from the Vivado utilisation reports; speed and latency from the
% board results (results/<tag>/results.bin) or, if those are not on this
% PC, from the board-run summary in reports/.
    tags = {'drhe', 'lpc', 'drhe_full', 'lpc_full'};
    for i = 1:numel(tags)
        rpt = first_existing({fullfile(fpgaDir, 'out', ['kcu116_' tags{i} '_util.rpt']), ...
                              fullfile(fpgaDir, 'reports', ['kcu116_' tags{i} '_util.rpt'])});
        hw.(tags{i}).util = read_util(rpt);
    end
    hw.source = '';
    for a = {'drhe', 'lpc'}
        rb = fullfile(fpgaDir, 'results', a{1}, 'results.bin');
        if exist(rb, 'file')
            fid = fopen(rb); w = fread(fid, [8 inf], 'uint32=>double'); fclose(fid);
            hw.(a{1}).cycles = mean(w(3, :));
            hw.(a{1}).latency_us = mean(w(8, :)) / 100;       % 100 MHz clock
            hw.source = [hw.source ' ' rb];
        else
            txt = fileread(fullfile(fpgaDir, 'reports', 'fpga_results_summary_kiem_dictionary.txt'));
            c = summary_pair(txt, 'Clock cycles per frame');
            l = summary_pair(txt, 'End-to-end latency');
            col = 1 + strcmp(a{1}, 'lpc');
            hw.(a{1}).cycles = c(col); hw.(a{1}).latency_us = l(col);
            hw.source = 'reports/fpga_results_summary_kiem_dictionary.txt';
        end
        frameBits = 128 * 192 * 4 * 2 * 16;
        hw.(a{1}).gibps = frameBits / (hw.(a{1}).cycles / 100e6) / 2^30;
    end
end

function u = read_util(rpt)
% [LUT BRAM DSP] fractions from a Vivado report_utilization file
    txt = fileread(rpt);
    u = [util_row(txt, 'CLB LUTs'), util_row(txt, 'Block RAM Tile'), util_row(txt, 'DSPs')];
end

function frac = util_row(txt, name)
    tok = regexp(txt, ['\|\s*' name '\*?\s*\|\s*([\d.]+)\s*\|[^|]*\|[^|]*\|\s*([\d.]+)\s*\|'], 'tokens', 'once');
    frac = str2double(tok{1}) / str2double(tok{2});
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

function s = fmt_num(v)
    if v >= 1000, s = regexprep(sprintf('%.0f', v), '(\d)(?=(\d{3})+$)', '$1,');
    elseif v >= 100, s = sprintf('%.0f', v);
    else, s = sprintf('%.1f', v); end
end

function f = newfig(w, h)
    f = figure('Units', 'inches', 'Position', [1 1 w h], 'Color', 'w', 'Visible', 'off');
end

function save_fig(f, outdir, name)
    exportgraphics(f, fullfile(outdir, name), 'Resolution', 300, 'BackgroundColor', 'white');
    close(f);
end
