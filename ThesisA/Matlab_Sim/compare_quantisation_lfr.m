function out = compare_quantisation_lfr(frameIndex, makePlots)
% COMPARE_QUANTISATION_LFR  Before/after study of fixed-point quantisation error
%   and its reduction via Low-Frequency Rejection (LFR) companding.
%
%   This script reproduces the fixed-point (FX16) quantisation error on a
%   ColoRadar cascade frame and then reduces it by replacing the uniform
%   fixed-scale quantiser with the two-stage low-frequency-suppression companding
%   curve of Deng & Huang (2024). It compares three fixed-point quantisers, all
%   feeding the same lossless DRHE coder:
%
%     (1) FX16-uniform : current pipeline  (compress_fx16) - worst-case fixed
%                        scale; most int16 codes are unused -> large error.
%     (2) FX16-linear  : adaptive linear stretch of the data peak to int16
%                        full-scale  (the paper's "traditional linear method").
%     (3) FX16-LFR     : two-stage low-frequency-suppression companding,
%                        parameters optimised to the data distribution.
%
%   The FP16 (floating-point) path is included as the fidelity reference the
%   fixed-point paths are trying to match.
%
%   Usage:
%     compare_quantisation_lfr            % frame 0, with plots
%     compare_quantisation_lfr(0,false)   % no plots
%     out = compare_quantisation_lfr(10); % return metrics struct
%
%   Output struct OUT carries the per-method metrics and the LFR parameters.

    if nargin < 1 || isempty(frameIndex); frameIndex = 0; end
    if nargin < 2 || isempty(makePlots);  makePlots  = true; end

    %% --- locate and load the frame ------------------------------------
    simDir  = fileparts(mfilename('fullpath'));
    candidatePaths = { ...
        fullfile(simDir, '..', '..', 'Jordan''s Thesis', 'cascade', 'adc_samples', 'data'), ...
        'C:\Users\mohin\Downloads\12_21_2020_ec_hallways_run4\12_21_2020_ec_hallways_run4\cascade\adc_samples\data' ...
    };

    binFile = '';
    for i = 1:length(candidatePaths)
        testFile = fullfile(candidatePaths{i}, sprintf('frame_%d.bin', frameIndex));
        if exist(testFile, 'file') == 2
            binFile = testFile;
            dataDir = candidatePaths{i};
            break;
        end
    end

    if isempty(binFile)
        error('compare_quantisation_lfr:notFound', 'Frame frame_%d.bin not found in candidate directories.', frameIndex);
    end

    opts = struct('txSelect', 1:12, 'removeDC', true, 'fx16EffectiveBits', 16);
    [cube, config, axesInfo] = loadColoRadarFrame(binFile, opts);

    %% --- reference processing chain (double precision) ----------------
    pre = preprocessing(cube, config);
    rf  = rangeFFT(pre, config);                       % complex double reference
    P_ref = computeFullScaleRefPower(config);
    [~, rdRef, ~] = secondStageProcessing(rf, config);

    L = 32767;

    %% --- build the four quantiser paths -------------------------------
    % FP16 (floating-point reference)
    fp  = compress_fp16(rf);
    rFP = decompress_fp16(fp);

    % FX16-uniform (current pipeline)
    cU  = compress_fx16(rf, config);
    rU  = decompress_fx16(cU);

    % FX16-linear (adaptive full-scale linear stretch = identity companding)
    parLin = struct('t', L, 'k', L, 'L', L, 'gt', lfr_inflection(L, L, L), ...
                    'Amax', max(abs(rf(:))), 'sigma', NaN);
    cL  = compress_fx16_lfr(rf, config, parLin);
    rL  = decompress_fx16_lfr(cL);

    % FX16-LFR (optimised companding)
    parLFR = lfr_optimize_params(abs(rf), L);
    cR  = compress_fx16_lfr(rf, config, parLFR);
    rR  = decompress_fx16_lfr(cR);

    %% --- DRHE (lossless) on each fixed-point code stream --------------
    dU = compress_drhe(cU, config);
    dL = compress_drhe(cL, config);
    dR = compress_drhe(cR, config);

    % verify DRHE round-trips the LFR codes losslessly, then decode end-to-end
    rR_drhe = decode_through_drhe(dR, parLFR);
    losslessErr = max(abs(rR_drhe(:) - rR(:)));

    %% --- metrics ------------------------------------------------------
    out = struct();
    out.frameIndex = frameIndex;
    out.lfrParams  = parLFR;
    out.drheLosslessMaxErr = losslessErr;

    out.FP16 = metricSet(rf, rFP, rdRef, config, P_ref, fp,  L, NaN);
    out.FX16uniform = metricSet(rf, rU, rdRef, config, P_ref, cU, L, dU.CR);
    out.FX16linear  = metricSet(rf, rL, rdRef, config, P_ref, cL, L, dL.CR);
    out.FX16lfr     = metricSet(rf, rR, rdRef, config, P_ref, cR, L, dR.CR);

    %% --- report -------------------------------------------------------
    fprintf('\n==================================================================================\n');
    fprintf('  QUANTISATION-ERROR STUDY  (ColoRadar frame %d)\n', frameIndex);
    fprintf('  LFR params: t=%.1f (%.2f%% of L)  k=%.4g  l=%.2f  p=%.3f  Rayleigh sigma=%.3g\n', ...
        parLFR.t, 100*parLFR.t/L, parLFR.k, parLFR.l, parLFR.p, parLFR.sigma);
    fprintf('  DRHE lossless check (LFR path), max code error = %g\n', losslessErr);
    fprintf('----------------------------------------------------------------------------------\n');
    fprintf('  %-14s %12s %12s %12s %12s %10s\n', ...
        'Method', 'relRMS %', 'magPSNR dB', 'RDerr dB', 'int16 use %', 'DRHE CR');
    fprintf('  %-14s %12s %12s %12s %12s %10s\n', ...
        '------', '--------', '---------', '--------', '----------', '-------');
    printRow('FP16(ref)',   out.FP16);
    printRow('FX16-uniform',out.FX16uniform);
    printRow('FX16-linear', out.FX16linear);
    printRow('FX16-LFR',    out.FX16lfr);
    fprintf('==================================================================================\n');

    impr = out.FX16lfr.magPSNR - out.FX16uniform.magPSNR;
    fprintf('  LFR vs uniform: magnitude PSNR +%.1f dB, relative-RMS error %.3f%% -> %.4f%%\n', ...
        impr, out.FX16uniform.relRMS_pct, out.FX16lfr.relRMS_pct);

    %% --- plots --------------------------------------------------------
    if makePlots
        plotQuantStudy(rf, rdRef, rU, rR, parLFR, L, config, P_ref, axesInfo, frameIndex);
    end
end

%% ======================================================================== %%
function m = metricSet(rf, rec, rdRef, config, P_ref, comp, L, drheCR)
    err = rec - rf;
    m.relRMS_pct = 100 * sqrt(mean(abs(err(:)).^2)) / sqrt(mean(abs(rf(:)).^2));

    Amax  = max(abs(rf(:)));
    mseMg = mean((abs(rec(:)) - abs(rf(:))).^2);
    m.magPSNR = 10 * log10(Amax^2 / (mseMg + eps));

    [~, rdTest, ~] = secondStageProcessing(rec, config);
    rdRefDB  = 10 * log10(rdRef  / P_ref + eps);
    rdTestDB = 10 * log10(rdTest / P_ref + eps);
    m.RDerr_dB = sqrt(mean((rdTestDB(:) - rdRefDB(:)).^2));   % RMS dB error on RD map

    if isfield(comp, 'real_part') && isa(comp.real_part, 'int16')
        codes = double([comp.real_part(:); comp.imag_part(:)]);
        m.int16use_pct = 100 * max(abs(codes)) / L;
    else
        m.int16use_pct = NaN;     % FP16 stores half-precision, not int16 codes
    end
    m.drheCR = drheCR;
end

%% ======================================================================== %%
function printRow(name, m)
    if isnan(m.int16use_pct); useStr = '     -'; else; useStr = sprintf('%.2f', m.int16use_pct); end
    fprintf('  %-14s %12.4f %12.2f %12.4f %12s %10s\n', ...
        name, m.relRMS_pct, m.magPSNR, m.RDerr_dB, useStr, crStr(m.drheCR));
end

function s = crStr(cr)
    if isnan(cr); s = '   -'; else; s = sprintf('%.3f', cr); end
end

%% ======================================================================== %%
function rec = decode_through_drhe(drheStruct, params)
% Decode the DRHE stream back to int16 codes, then invert the LFR companding.
    codesC = decompress_drhe(drheStruct);     % scaleFactor=1 -> returns the codes
    s = struct('real_part', int16(round(real(codesC))), ...
               'imag_part', int16(round(imag(codesC))), ...
               'scaleFactor', 1, 'lfrParams', params);
    rec = decompress_fx16_lfr(s);
end

%% ======================================================================== %%
function plotQuantStudy(rf, rdRef, rU, rR, params, L, config, P_ref, axesInfo, frameIndex)
    useReal = ~isempty(axesInfo) && isfield(axesInfo,'realData') && axesInfo.realData;
    if useReal
        xAx = axesInfo.velAxis; yAx = axesInfo.rangeAxis;
        xLbl = 'Velocity (m/s)'; yLbl = 'Range (m)';
    else
        xAx = 0:config.numRamps-1; yAx = 0:size(rdRef,1)-1;
        xLbl = 'Doppler bin'; yLbl = 'Range bin';
    end

    [~, rdU, ~] = secondStageProcessing(rU, config);
    [~, rdR, ~] = secondStageProcessing(rR, config);
    refDB = 10*log10(rdRef/P_ref + eps);
    uDB   = 10*log10(rdU /P_ref + eps);
    rDB   = 10*log10(rdR /P_ref + eps);
    if useReal
        refDB = fftshift(refDB,2); uDB = fftshift(uDB,2); rDB = fftshift(rDB,2);
    end
    cmax = max(refDB(:)); cmin = cmax - 60;

    figure('Name','LFR quantisation study','NumberTitle','off','Position',[60 60 1500 900]);

    % (1) companding curve
    subplot(2,3,1);
    xx = linspace(0, L, 1000);
    yy = lfr_g(xx, params);
    plot(xx/L*100, yy/L*100, 'b-', 'LineWidth', 1.8); hold on;
    plot([0 100],[0 100],'k--');
    xline(100*params.t/L, 'r:', 'LineWidth',1.2);
    hold off; grid on; axis([0 100 0 100]);
    xlabel('input magnitude (% of peak)'); ylabel('companded code (% of int16 FS)');
    title(sprintf('LFR companding curve (t=%.1f%%, k=%.3g)', 100*params.t/L, params.k));
    legend('g(x)','identity (linear)','threshold t','Location','southeast');

    % (2) magnitude histogram (log) showing concentration
    subplot(2,3,4);
    mag = abs(rf(:)); mag = mag(mag>0)/max(abs(rf(:)))*100;
    histogram(mag, 100); set(gca,'YScale','log');
    xlabel('magnitude (% of peak)'); ylabel('count (log)');
    title('Range-FFT magnitude distribution (concentrated near 0)');

    % (3) reference RD map
    subplot(2,3,2);
    imagesc(xAx, yAx, refDB); axis xy; colormap(jet); colorbar; clim([cmin cmax]);
    xlabel(xLbl); ylabel(yLbl); title('Reference RD map (double) [dBFS]');
    applyLims(useReal, axesInfo);

    % (4) FX16-uniform error vs reference
    subplot(2,3,3);
    imagesc(xAx, yAx, uDB - refDB); axis xy; colormap(jet); colorbar;
    xlabel(xLbl); ylabel(yLbl); title('FX16-uniform error [dB] (current)');
    applyLims(useReal, axesInfo);

    % (5) FX16-LFR error vs reference
    subplot(2,3,6);
    imagesc(xAx, yAx, rDB - refDB); axis xy; colormap(jet); colorbar;
    xlabel(xLbl); ylabel(yLbl); title('FX16-LFR error [dB] (proposed)');
    applyLims(useReal, axesInfo);

    % (6) per-magnitude reconstruction error: uniform vs LFR
    subplot(2,3,5);
    magTrue = abs(rf(:));
    errU = abs(abs(rU(:)) - magTrue);
    errR = abs(abs(rR(:)) - magTrue);
    [magS, si] = sort(magTrue);
    nb = 40; edges = linspace(0, max(magS), nb+1);
    [~,~,bin] = histcounts(magS, edges);
    eu = accumarray(bin(bin>0), errU(si(bin>0)), [nb 1], @mean, NaN);
    er = accumarray(bin(bin>0), errR(si(bin>0)), [nb 1], @mean, NaN);
    ctr = (edges(1:end-1)+edges(2:end))/2 / max(magS) * 100;
    plot(ctr, eu, 'r-o','MarkerSize',3); hold on; plot(ctr, er, 'b-s','MarkerSize',3); hold off;
    grid on; set(gca,'YScale','log');
    xlabel('magnitude (% of peak)'); ylabel('mean |magnitude error|');
    legend('FX16-uniform','FX16-LFR','Location','northwest');
    title('Reconstruction error vs magnitude');

    sgtitle(sprintf('Fixed-point quantisation error & LFR reduction (frame %d)', frameIndex));
end

function applyLims(useReal, axesInfo)
    if ~useReal; return; end
    ylim([0 axesInfo.rangeMaxPlot]);
    if ~isempty(axesInfo.velMaxPlot)
        xlim([-axesInfo.velMaxPlot axesInfo.velMaxPlot]);
    end
end
