%% RUN_KIEM_REPLICATION
%  Independent re-implementation of Lukas Kiem's MATLAB simulation workflow
%  (Kiem 2025, Chapter 3, Figure 3.1) for his single-transmitter radar, with
%  his simulated scene (Table 3.2), his preprocessing and range FFT (3.2.1),
%  his design space (Table 3.4), his final DRHE scheme (3.5.3), the
%  LPC-Huffman method he cites (2.7.4), his 2nd-stage processing and his
%  metrics (3.4.2). Nothing outside this folder is used.
%
%  Output: the Table 3.5 layout for the replicated scene, next to Kiem's own
%  numbers, plus figures in the style of his Figures 3.5, 3.7 and 3.13,
%  written to ./results.
%
%  Run time: about one minute. See README.md for every assumption.

clear; close all;
here = fileparts(mfilename('fullpath'));
addpath(here);
outDir = fullfile(here, 'results');
if ~exist(outDir, 'dir'), mkdir(outDir); end
logFile = fullfile(outDir, 'run_kiem_replication_log.txt');
if exist(logFile, 'file'), delete(logFile); end
diary(logFile);

SCENARIO = 'sim';            % 'sim' = Kiem Table 3.2, 'usecase' = Table 3.3
cfg = kr_config(SCENARIO);

fprintf('================================================================\n');
fprintf(' Replication of Kiem''s simulation workflow (scenario "%s")\n', SCENARIO);
fprintf(' %d MMIC, %d TX, %d RX, %d samples x %d ramps, %d-bit ADC\n', ...
    cfg.numMMIC, cfg.numTx, cfg.numRx, cfg.numSamples, cfg.numRamps, cfg.bitWidth);
fprintf(' Targets (range bin / Doppler bin / amplitude):\n');
fprintf('   %3d / %3d / %.1f\n', [cfg.targets.rangeBin; cfg.targets.dopplerBin; cfg.targets.amplitude]);
fprintf(' Noise after NCI: %.1f dBFS   FX16: %s   dBFS: %s\n', ...
    cfg.noiseAfterNCI_dBFS, cfg.fx16Mode, cfg.dbfsMode);
fprintf('================================================================\n');

% Two operating points: Kiem's stated noise level for this scene [Table 3.2],
% and the noise level at which DRHE reaches the CR he published (3.25 with
% R4S4 + RLE, Table 3.5), found by bisection.
nfMatch = kr_find_nf_for_cr(cfg, 3.25, 'DRHE_RLE');
points = {cfg.noiseAfterNCI_dBFS, 'Kiem Table 3.2 noise level';
          nfMatch, 'noise level at which DRHE gives Kiem''s CR of 3.25'};
for ip = 1:2
NFrun = points{ip, 1};
fprintf('\n################################################################\n');
fprintf(' OPERATING POINT %d: %s (%.1f dBFS after NCI)\n', ip, points{ip, 2}, NFrun);
fprintf('################################################################\n');
tic;
res = kr_run_scene(cfg, struct('noiseNF', NFrun));
fprintf(' run time %.1f s\n', toc);
fprintf(' ADC noise sigma = %.2f codes (%.1f dB below full scale), clipped %.4f %%\n', ...
    res.sigmaLSB, 20*log10((2^(cfg.bitWidth-1)-1)/res.sigmaLSB), 100*res.clipped);
fprintf(' FX16 codes: max |x| = %d (%d of 16 bits used), noise-only std = %.2f codes, zeros = %.1f %%\n', ...
    res.fx16.maxAbs, res.fx16.bitsUsed, res.fx16.noiseOnlyStd, 100*res.fx16.zeroFrac);
fprintf(' Lossless round trips: DRHE %d, LPC (slow time) %d, LPC-Huffman raw %d\n', ...
    res.drheLossless, res.lpcFFTLossless, res.lpcRawLossless);
fprintf(' Reference (FP16) detections: %d\n', res.nRef);

rows = {
 'FP16',          'FP16',          'FP16 (reference)'
 'FX16',          'FX16',          'FX16'
 'CMPRA',         'CMPRA',         'CMPRA (approx.)'
 'CMPRB',         'CMPRB',         'CMPRB (approx.)'
 'EGE10',         'EGE10',         'EGE10 (approx.)'
 'EGE8',          'EGE8',          'EGE8 (approx.)'
 'EGE6',          'EGE6',          'EGE6 (approx.)'
 'EGE4',          'EGE4',          'EGE4 (approx.)'
 'DRHE_RLE',      'DRHE',          'DRHE, R4S4 + RLE, ideal Huffman'
 'DRHE_noRLE',    'DRHE_noRLE',    'DRHE, S4 only, ideal Huffman'
 'DRHE_fixed',    '',              'DRHE, S4, fixed dictionary (HW)'
 'LPC_raw',       '',              'LPC-Huffman on raw ADC [25]'
 'LPC_FFT',       '',              'LPC slow time, fixed dict (thesis)'
 'LPC_FFT_ideal', '',              'LPC slow time, ideal Huffman'
 'NoPred',        '',              'No prediction, fixed dictionary'
 'NoPred_RLE',    '',              'No prediction, R4S4 + RLE, ideal'
 };
K = kr_kiem_table();
fprintf('\n Replicated Table 3.5 (this scene)                           | Kiem Table 3.5 (his data)\n');
fprintf(' %-36s %6s %6s %6s %9s %7s | %5s %5s %5s %8s %6s\n', 'Algorithm', 'CR', 'FN%', 'FP%', 'NF dBFS', 'SNR', 'CR', 'FN%', 'FP%', 'NF', 'SNR');
for k = 1:size(rows, 1)
    m = res.metrics.(rows{k,1});
    fprintf(' %-36s %6.2f %6.2f %6.2f %9.2f %7.2f |', rows{k,3}, m.CR, m.FN_pct, m.FP_pct, m.NF, m.SNR);
    if ~isempty(rows{k,2}) && isfield(K, rows{k,2})
        q = K.(rows{k,2});
        fprintf(' %5.2f %5.2f %5.2f %8.2f %6.2f\n', q);
    else
        fprintf('\n');
    end
end
fprintf(' Range-Doppler cells coded to exactly zero (excluded from NF and the\n detector''s noise estimate): ');
for nm = {'CMPRA', 'CMPRB', 'EGE10', 'EGE8', 'EGE6', 'EGE4'}
    fprintf('%s %.1f %%  ', nm{1}, res.metrics.(nm{1}).zeroCellPct);
end
fprintf('\n');
fprintf('\n LPC-Huffman on raw ADC, by order p (CR with dictionary / without):\n');
for p = cfg.lpcRawOrders
    o = res.lpcRaw(p);
    fprintf('   p = %2d : %5.3f / %5.3f   residual std %.1f codes\n', p, o.CR, o.CRnoDict, o.residualStd);
end
fprintf(' Best order p = %d. Kiem quotes CR 2.056 for this method on the data of [25].\n', res.lpcRawBest.order);
fprintf(' NF with the other dBFS reference (''unit''): FX16 %.2f dBFS\n', res.metrics.FX16.NF_unit);

allRes{ip} = res; %#ok<SAGROW>
end
res = allRes{1};
for ip = 1:2
    r = allRes{ip};
    summary(ip) = struct('noiseNF', points{ip,1}, 'label', points{ip,2}, ...
        'metrics', r.metrics, 'sigmaLSB', r.sigmaLSB, 'fx16', r.fx16, ...
        'nRef', r.nRef, 'lpcRawBest', r.lpcRawBest); %#ok<SAGROW>
end
save(fullfile(outDir, 'kiem_replication_results.mat'), 'summary', 'cfg');
kr_figures(res, cfg, outDir);
diary off;
fprintf('\n Results, log and figures written to %s\n', outDir);
