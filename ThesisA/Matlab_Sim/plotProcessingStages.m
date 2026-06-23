function plotProcessingStages(rangeFFTData, dopplerFFTData, rdMap, config)
% PLOTPROCESSINGSTAGES Generates plots matching Figures 3.5-3.7 of Kiem's thesis.
%   Figure 3.5: Range FFT output for ramp 1 and RX antenna 1 (magnitude in dB)
%   Figure 3.6: 3D range-Doppler image after NCI
%   Figure 3.7: 2D heatmaps at processing pipeline stages
%
%   Input:
%     rangeFFTData   - complex [numRangeBins x numRamps x numRxChannels]
%     dopplerFFTData - complex [numRangeBins x numRamps x numRxChannels]
%     rdMap          - real [numRangeBins x numRamps] (power after NCI)
%     config         - configuration struct

    nRangeBins = size(rangeFFTData, 1);
    nRamps     = config.numRamps;

    % Compute dBFS reference for consistent scaling
    fullScaleRefPower = computeFullScaleRefPower(config);

    % =====================================================================
    % Figure 3.5: Range FFT output for ramp 1 and RX antenna 1
    % =====================================================================
    figure('Name', 'Figure 3.5 - Range FFT Output', 'NumberTitle', 'off');

    rangeSlice = rangeFFTData(:, 1, 1);
    % Single-channel, single-ramp reference: use amplitude relative to full-scale
    shift = 16 - config.bitWidth + 16;
    maxADCVal = 2^(config.bitWidth - 1) - 1;
    hannR = hanning(config.numSamples);
    fsAmplitude = maxADCVal * 2^shift * sum(hannR) / (2 * config.numSamples);
    magnitudeDBFS = 20 * log10(abs(rangeSlice) / fsAmplitude + eps);

    plot(0:nRangeBins-1, magnitudeDBFS, 'b', 'LineWidth', 0.8);
    xlabel('Range Bin');
    ylabel('Magnitude (dBFS)');
    title('Simulated Data: Range FFT Output for Ramp 1 and RX Antenna 1');
    grid on;
    xlim([0 nRangeBins-1]);

    % =====================================================================
    % Figure 3.6: 3D Range-Doppler image after NCI
    % =====================================================================
    figure('Name', 'Figure 3.6 - 3D Range-Doppler Map', 'NumberTitle', 'off');

    rdMapDBFS = 10 * log10(rdMap / fullScaleRefPower + eps);

    rangeBins = 0:nRangeBins-1;
    dopplerBins = 0:nRamps-1;

    mesh(dopplerBins, rangeBins, rdMapDBFS);
    xlabel('Doppler Bin');
    ylabel('Range Bin');
    zlabel('Magnitude (dBFS)');
    title('Simulated Data: 3D Range-Doppler Image after NCI');
    colormap('jet');
    view([-37.5, 30]);

    % =====================================================================
    % Figure 3.7: 2D heatmaps at different processing stages
    % =====================================================================
    figure('Name', 'Figure 3.7 - 2D Heatmaps', 'NumberTitle', 'off');

    % (a) Range-Ramp map after Range FFT computation
    subplot(1, 3, 1);
    rangeRampMap = 20 * log10(abs(rangeFFTData(:, :, 1)) / fsAmplitude + eps);
    imagesc(0:nRamps-1, 0:nRangeBins-1, rangeRampMap);
    xlabel('Ramp Index');
    ylabel('Range Bin');
    title('(a) Range-Ramp Map (after Range FFT)');
    colorbar;
    colormap('jet');
    axis xy;
    clim([-100, 0]);

    % (b) Range-Doppler map after Doppler FFT (single RX channel)
    subplot(1, 3, 2);
    hannD = hanning(nRamps);
    fsSingleChannel = fsAmplitude * sum(hannD) / nRamps;
    rangeDopplerSingle = 20 * log10(abs(dopplerFFTData(:, :, 1)) / fsSingleChannel + eps);
    imagesc(0:nRamps-1, 0:nRangeBins-1, rangeDopplerSingle);
    xlabel('Doppler Bin');
    ylabel('Range Bin');
    title('(b) Range-Doppler Map (after Doppler FFT)');
    colorbar;
    colormap('jet');
    axis xy;
    clim([-100, 0]);

    % (c) Range-Doppler map after NCI
    subplot(1, 3, 3);
    imagesc(0:nRamps-1, 0:nRangeBins-1, rdMapDBFS);
    xlabel('Doppler Bin');
    ylabel('Range Bin');
    title('(c) Range-Doppler Map (after NCI)');
    colorbar;
    colormap('jet');
    axis xy;
    clim([-100, 0]);

    sgtitle('Simulated Data: 2D Heatmaps at Processing Pipeline Stages');
end
