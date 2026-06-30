function plotCompressionComparison(rdMapFP16, rdMapFX16, config, fullScaleRefPower, axesInfo)
% PLOTCOMPRESSIONCOMPARISON Visualises the fixed- vs floating-point quantisation error.
%   Shows the Range-Doppler map (dBFS) for the FP16 (floating-point) and
%   FX16 (fixed-point) paths side by side, with the weak targets circled, plus
%   the FX16-FP16 difference. The fixed-point pipeline quantises the range-FFT
%   onto a uniform grid (reduced effective bit-depth), which truncates the
%   low-level detail that floating-point preserves. The circled weak targets and
%   the difference panel make that quantisation error visible.
%
%   Input:
%     rdMapFP16         - Range-Doppler power map from the FP16 path
%     rdMapFX16         - Range-Doppler power map from the FX16 path
%     config            - configuration struct (uses .fx16EffectiveBits and,
%                         if present, .weakTargetIdx / .targetRangeBins /
%                         .targetDopplerBins to circle the weak targets)
%     fullScaleRefPower - 0 dBFS reference power
%     axesInfo          - (optional) physical-axis struct from loadRealRadarCube;
%                         when .realData is true the maps are drawn against real
%                         range (m) / velocity (m/s) with the Doppler axis
%                         fftshifted. (Synthetic weak-target circles are skipped
%                         for real data, which has no ground-truth target list.)

    if nargin < 5; axesInfo = []; end
    useReal = ~isempty(axesInfo) && isfield(axesInfo, 'realData') && axesInfo.realData;

    [nRangeBins, nRamps] = size(rdMapFP16);

    fpDBFS = 10 * log10(rdMapFP16 / fullScaleRefPower + eps);
    fxDBFS = 10 * log10(rdMapFX16 / fullScaleRefPower + eps);
    diffDB = fxDBFS - fpDBFS;   % quantisation error of FX16 relative to FP16

    if useReal
        fpDBFS = fftshift(fpDBFS, 2);
        fxDBFS = fftshift(fxDBFS, 2);
        diffDB = fftshift(diffDB, 2);
        xAx = axesInfo.velAxis;  yAx = axesInfo.rangeAxis;
    else
        xAx = 0:nRamps-1;  yAx = 0:nRangeBins-1;
    end

    % Colour scale: 60 dB window from the strongest return down, so both the
    % noise floor and the faint targets are visible.
    cmax = max(fpDBFS(:));
    cmin = cmax - 60;

    if isfield(config, 'fx16EffectiveBits')
        enob = config.fx16EffectiveBits;
    else
        enob = 16;
    end

    % Locations of the weak targets to circle (synthetic ground truth only;
    % real captures have no target list, so nothing is circled).
    if ~useReal && isfield(config, 'weakTargetIdx') && ~isempty(config.weakTargetIdx) && ...
            isfield(config, 'targetRangeBins') && isfield(config, 'targetDopplerBins')
        wIdx = config.weakTargetIdx;
        weakR = config.targetRangeBins(wIdx);
        weakD = config.targetDopplerBins(wIdx);
    else
        weakR = [];
        weakD = [];
    end

    if useReal
        xLbl = 'Velocity (m/s)'; yLbl = 'Range (m)';
    else
        xLbl = 'Doppler Bin'; yLbl = 'Range Bin';
    end
    applyLims = @() applyRealLims(useReal, axesInfo);

    figure('Name', 'FP16 vs FX16 - Quantisation Error', 'NumberTitle', 'off', ...
        'Position', [80 120 1500 620]);

    subplot(1, 3, 1);
    imagesc(xAx, yAx, fpDBFS);
    axis xy; colormap('jet'); colorbar; clim([cmin cmax]);
    hold on;
    if ~isempty(weakR)
        plot(weakD, weakR, 'wo', 'MarkerSize', 12, 'LineWidth', 1.5);
    end
    hold off;
    xlabel(xLbl); ylabel(yLbl); applyLims();
    if useReal
        title('FP16 (floating-point)');
    else
        title({'FP16 (floating-point)', 'weak targets preserved (circled)'});
    end

    subplot(1, 3, 2);
    imagesc(xAx, yAx, fxDBFS);
    axis xy; colormap('jet'); colorbar; clim([cmin cmax]);
    hold on;
    if ~isempty(weakR)
        plot(weakD, weakR, 'wo', 'MarkerSize', 12, 'LineWidth', 1.5);
    end
    hold off;
    xlabel(xLbl); ylabel(yLbl); applyLims();
    if useReal
        title(sprintf('FX16 (fixed-point, %d-bit eff.)', enob));
    else
        title({sprintf('FX16 (fixed-point, %d-bit eff.)', enob), 'quantisation degrades circled targets'});
    end

    subplot(1, 3, 3);
    imagesc(xAx, yAx, diffDB);
    axis xy; colormap('jet'); colorbar;
    xlabel(xLbl); ylabel(yLbl); applyLims();
    title({'FX16 - FP16 difference [dB]', '(quantisation noise)'});

    sgtitle('Quantisation Error: Floating-Point vs Fixed-Point');
end

%% ----------------------------------------------------------------------- %%
function applyRealLims(useReal, axesInfo)
    if ~useReal; return; end
    ylim([0 axesInfo.rangeMaxPlot]);
    if ~isempty(axesInfo.velMaxPlot)
        xlim([-axesInfo.velMaxPlot axesInfo.velMaxPlot]);
    end
end
