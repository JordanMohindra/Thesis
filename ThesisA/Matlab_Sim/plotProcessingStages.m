function plotProcessingStages(rangeFFTData, dopplerFFTData, rdMap, config, axesInfo)
% PLOTPROCESSINGSTAGES Generates plots matching Figures 3.5-3.7 of Kiem's thesis.
%   Figure 3.5: Range FFT output for ramp 1 and RX antenna 1 (magnitude in dB)
%   Figure 3.6: 3D range-Doppler image after NCI (the "3D cloud" of object placement)
%   Figure 3.7: 2D heatmaps at processing pipeline stages
%
%   Input:
%     rangeFFTData   - complex [numRangeBins x numRamps x numRxChannels]
%     dopplerFFTData - complex [numRangeBins x numRamps x numRxChannels]
%     rdMap          - real [numRangeBins x numRamps] (power after NCI)
%     config         - configuration struct
%     axesInfo       - (optional) physical-axis struct from loadRealRadarCube:
%                      .realData, .rangeAxis (m), .velAxis (m/s),
%                      .rangeMaxPlot, .velMaxPlot. When present and .realData is
%                      true the plots are drawn against real range/velocity (with
%                      the Doppler axis fftshifted so 0 m/s is centred), so the
%                      3D image shows the true physical placement of each object.

    if nargin < 5; axesInfo = []; end
    useReal = ~isempty(axesInfo) && isfield(axesInfo, 'realData') && axesInfo.realData;

    nRangeBins = size(rangeFFTData, 1);
    nRamps     = config.numRamps;

    % Compute dBFS reference for consistent scaling
    fullScaleRefPower = computeFullScaleRefPower(config);

    % Single-channel, single-ramp full-scale amplitude (for dB normalisation)
    shift = 16 - config.bitWidth + 16;
    maxADCVal = 2^(config.bitWidth - 1) - 1;
    hannR = hanning(config.numSamples);
    fsAmplitude = maxADCVal * 2^shift * sum(hannR) / (2 * config.numSamples);

    rdMapDBFS = 10 * log10(rdMap / fullScaleRefPower + eps);

    % Physical vs bin axes
    if useReal
        xVel = axesInfo.velAxis;            % m/s   (length nRamps)
        yRng = axesInfo.rangeAxis;          % m     (length nRangeBins)
        rdDisp = fftshift(rdMapDBFS, 2);    % centre zero-Doppler
        cmaxRD = max(rdDisp(:)); cminRD = cmaxRD - 60;
        sceneTag = 'Real Data';
    else
        xVel = 0:nRamps-1;                  % Doppler bin
        yRng = 0:nRangeBins-1;             % range bin
        rdDisp = rdMapDBFS;
        cminRD = -100; cmaxRD = 0;
        sceneTag = 'Simulated Data';
    end

    % =====================================================================
    % Figure 3.5: Range FFT output for ramp 1 and RX antenna 1
    % =====================================================================
    figure('Name', 'Figure 3.5 - Range FFT Output', 'NumberTitle', 'off');
    rangeSlice = rangeFFTData(:, 1, 1);
    magnitudeDBFS = 20 * log10(abs(rangeSlice) / fsAmplitude + eps);
    plot(yRng, magnitudeDBFS, 'b', 'LineWidth', 0.8);
    if useReal
        xlabel('Range (m)'); xlim([0 axesInfo.rangeMaxPlot]);
    else
        xlabel('Range Bin'); xlim([0 nRangeBins-1]);
    end
    ylabel('Magnitude (dBFS)');
    title(sprintf('%s: Range FFT Output for Ramp 1 and RX Antenna 1', sceneTag));
    grid on;

    % =====================================================================
    % Figure 3.6: 3D Range-Doppler image after NCI  (object placement cloud)
    % =====================================================================
    figure('Name', 'Figure 3.6 - 3D Range-Doppler Map', 'NumberTitle', 'off');
    mesh(xVel, yRng, rdDisp);
    zlabel('Magnitude (dBFS)');
    colormap('jet');
    view([-37.5, 30]);
    if useReal
        xlabel('Velocity (m/s)'); ylabel('Range (m)');
        ylim([0 axesInfo.rangeMaxPlot]);
        if ~isempty(axesInfo.velMaxPlot)
            xlim([-axesInfo.velMaxPlot axesInfo.velMaxPlot]);
        end
        zlim([cminRD cmaxRD]); clim([cminRD cmaxRD]);
    else
        xlabel('Doppler Bin'); ylabel('Range Bin');
    end
    title(sprintf('%s: 3D Range-Doppler Image after NCI', sceneTag));

    % =====================================================================
    % Figure 3.7: 2D heatmaps at different processing stages
    % =====================================================================
    figure('Name', 'Figure 3.7 - 2D Heatmaps', 'NumberTitle', 'off');

    % (a) Range-Ramp map after Range FFT computation (slow-time, pre Doppler FFT)
    subplot(1, 3, 1);
    rangeRampMap = 20 * log10(abs(rangeFFTData(:, :, 1)) / fsAmplitude + eps);
    imagesc(0:nRamps-1, yRng, rangeRampMap);
    xlabel('Ramp Index');
    applyRangeY(useReal, axesInfo, 'Range (m)', 'Range Bin');
    title('(a) Range-Ramp Map (after Range FFT)');
    colorbar; colormap('jet'); axis xy;
    if useReal; clim([max(rangeRampMap(:))-60, max(rangeRampMap(:))]); else; clim([-100, 0]); end

    % (b) Range-Doppler map after Doppler FFT (single RX channel)
    subplot(1, 3, 2);
    hannD = hanning(nRamps);
    fsSingleChannel = fsAmplitude * sum(hannD) / nRamps;
    rangeDopplerSingle = 20 * log10(abs(dopplerFFTData(:, :, 1)) / fsSingleChannel + eps);
    if useReal; rangeDopplerSingle = fftshift(rangeDopplerSingle, 2); end
    imagesc(xVel, yRng, rangeDopplerSingle);
    applyDopplerX(useReal, axesInfo);
    applyRangeY(useReal, axesInfo, 'Range (m)', 'Range Bin');
    title('(b) Range-Doppler Map (after Doppler FFT)');
    colorbar; colormap('jet'); axis xy;
    if useReal; clim([cminRD cmaxRD]); else; clim([-100, 0]); end

    % (c) Range-Doppler map after NCI
    subplot(1, 3, 3);
    imagesc(xVel, yRng, rdDisp);
    applyDopplerX(useReal, axesInfo);
    applyRangeY(useReal, axesInfo, 'Range (m)', 'Range Bin');
    title('(c) Range-Doppler Map (after NCI)');
    colorbar; colormap('jet'); axis xy;
    clim([cminRD cmaxRD]);

    sgtitle(sprintf('%s: 2D Heatmaps at Processing Pipeline Stages', sceneTag));
end

%% ----------------------------------------------------------------------- %%
function applyDopplerX(useReal, axesInfo)
    if useReal
        xlabel('Velocity (m/s)');
        if ~isempty(axesInfo.velMaxPlot)
            xlim([-axesInfo.velMaxPlot axesInfo.velMaxPlot]);
        end
    else
        xlabel('Doppler Bin');
    end
end

function applyRangeY(useReal, axesInfo, realLbl, binLbl)
    if useReal
        ylabel(realLbl); ylim([0 axesInfo.rangeMaxPlot]);
    else
        ylabel(binLbl);
    end
end
