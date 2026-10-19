function [T, perFrame] = run_coloradar_benchmark(opts)
% RUN_COLORADAR_BENCHMARK Stage 1: every compression algorithm on ColoRadar.
%   Function form of main_simulation_coloradar_batch.m. Runs the full
%   pipeline (runCompressionSim) on each frame and returns the global
%   averages: CR, FN %, FP %, noise floor and SNR, one row per algorithm.
%
%   [T, perFrame] = run_coloradar_benchmark(opts)
%   opts fields (all optional):
%     nFrames      number of frames (default 50, inf = all)
%     dataDir      folder with frame_*.bin ('' = find_coloradar_data)
%     txSelect     TX antennas (default 1:12)
%     fx16Enob     effective FX16 bits (default 16)
%     removeDC     subtract per-ramp mean (default true)
%     predLag      DRHE / LPC prediction lag ([] = nTx, i.e. per transmitter;
%                  1 = the old consecutive-ramp predictor)
%     verbose      print progress (default true)
%
%   T        table: Algorithm, CR, FN_pct, FP_pct, NF_dBFS, SNR_dB
%   perFrame struct array with each frame's metrics

    if nargin < 1, opts = struct(); end
    opts = setdef(opts, 'nFrames', 50);
    opts = setdef(opts, 'dataDir', '');
    opts = setdef(opts, 'txSelect', 1:12);
    opts = setdef(opts, 'fx16Enob', 16);
    opts = setdef(opts, 'removeDC', true);
    opts = setdef(opts, 'predLag', []);
    opts = setdef(opts, 'verbose', true);

    [dataDir, frameFiles] = find_coloradar_data(opts.dataDir);
    nFrames = min(opts.nFrames, numel(frameFiles));

    algorithms = {'FP16', 'DRHEfp16', 'FX16', 'DRHE', 'BAQ', 'RDVLE', 'RDVLE_UDRE', 'LPC_Huffman'};
    nA = numel(algorithms);
    sumCR = zeros(1, nA); sumNF = zeros(1, nA); sumSNR = zeros(1, nA);
    totFN = zeros(1, nA); totFP = zeros(1, nA); totTest = zeros(1, nA);
    totRef = 0; nDone = 0;
    perFrame = struct('frame', {}, 'refDetections', {}, 'CR', {}, 'FN_pct', {}, 'FP_pct', {});

    loadOpts = struct('txSelect', opts.txSelect, 'removeDC', opts.removeDC, ...
                      'fx16EffectiveBits', opts.fx16Enob, 'rangeMaxPlot', 25, 'velMaxPlot', []);

    for f = 1:nFrames
        binFile = fullfile(dataDir, frameFiles(f).name);
        if opts.verbose, fprintf('  stage 1: %s (%d/%d)\n', frameFiles(f).name, f, nFrames); end
        [~, cube, config] = evalc('loadColoRadarFrame(binFile, loadOpts)');
        if ~isempty(opts.predLag), config.predLag = opts.predLag; end
        fullScaleRefPower = computeFullScaleRefPower(config);
        [~, results] = evalc('runCompressionSim(config, fullScaleRefPower, frameFiles(f).name, cube)');

        refDet = results.refDetections;
        totRef = totRef + refDet;
        pf.frame = f - 1; pf.refDetections = refDet;
        pf.CR = zeros(1, nA); pf.FN_pct = zeros(1, nA); pf.FP_pct = zeros(1, nA);
        for i = 1:nA
            m = results.(['metrics' algorithms{i}]);
            fn = round(m.FN_pct / 100 * refDet);
            tp = refDet - fn;
            if m.FP_pct < 100
                testDet = tp / (1 - m.FP_pct / 100);
                fp = round(testDet - tp);
            else
                fp = 0;
            end
            totFN(i) = totFN(i) + fn; totFP(i) = totFP(i) + fp; totTest(i) = totTest(i) + tp + fp;
            sumCR(i) = sumCR(i) + m.CR; sumNF(i) = sumNF(i) + m.NF_dBFS; sumSNR(i) = sumSNR(i) + m.SNR_dB;
            pf.CR(i) = m.CR; pf.FN_pct(i) = m.FN_pct; pf.FP_pct(i) = m.FP_pct;
        end
        perFrame(end + 1) = pf; %#ok<AGROW>
        nDone = nDone + 1;
    end

    FN = 100 * totFN / max(totRef, 1);
    FP = 100 * totFP ./ max(totTest, 1);
    T = table(algorithms(:), (sumCR / nDone)', FN', FP', (sumNF / nDone)', (sumSNR / nDone)', ...
        'VariableNames', {'Algorithm', 'CR', 'FN_pct', 'FP_pct', 'NF_dBFS', 'SNR_dB'});
end

function s = setdef(s, f, v)
    if ~isfield(s, f) || (isempty(s.(f)) && ~isempty(v) && ~strcmp(f, 'predLag') && ~strcmp(f, 'dataDir'))
        s.(f) = v;
    end
end
