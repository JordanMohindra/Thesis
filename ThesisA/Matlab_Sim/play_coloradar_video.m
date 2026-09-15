%% Play ColoRadar cascade frames as an animated 3-pane video
%  Walks through every frame_<N>.bin in the ColoRadar capture and updates a
%  single figure with three live panes:
%
%    1) Range-Doppler heatmap (range vs velocity, NCI summed over RX)
%       The "what does the radar see right now" view. TDM-MIMO TX aliases
%       show up as 12 vertical stripes per real target - that is normal for
%       a MIMO Doppler-FFT view.
%
%    2) Range-Azimuth top-down image ("birdseye")
%       Beamforms across the 16 RX channels of a single TX. Range on Y,
%       azimuth angle on X. Use this to see the geometric scene -- where
%       things are relative to the radar.
%
%    3) Range-vs-frame waterfall
%       Per-frame range profile (max over Doppler & channels) plotted as a
%       new column on each frame. Lets you see targets moving in range
%       over time even when they are too slow to show clearly on the RD map.
%
%  PLAYBACK
%   Live in a MATLAB figure window. No video file is written. To stop, press
%   Ctrl+C or close the window.
%
%  REQUIREMENTS
%   loadColoRadarFrame.m and the rest of the Matlab_Sim pipeline in the same
%   folder. The script auto-discovers all frame_<N>.bin files under
%   ../../Jordan's Thesis/cascade/adc_samples/data.

clear; clc; close all;

%% ============ CONFIGURATION (edit these) ==========================
FRAME_RANGE = [];      % [] = all available frames, or e.g. 0:99 for first 100
TARGET_FPS  = 8;       % desired playback rate (cap; live processing may be slower)
% Colour limits are auto-fit from the first frame if you leave these as [].
% Set to [lo hi] in dBFS to override (e.g. [-80 -10] for a fixed scale).
DB_LIMITS_RD = [];           % Range-Doppler pane colour scale (dBFS)
DB_LIMITS_RA = [];           % Range-Azimuth pane colour scale (dBFS)
DB_LIMITS_WF = [];           % Waterfall pane colour scale (dBFS)
RANGE_MAX_PLOT = 10;          % [m] cap for all range axes
WATERFALL_LEN  = 120;         % how many recent frames to keep in the waterfall
AZ_TX_SELECT   = 1;           % TX index used for the RA pane (1 TX -> 16 RX ULA)
AZ_ZEROPAD     = 4;           % azimuth FFT zero-pad factor (1 = 16 bins, 4 = 64 bins)
% ===================================================================

%% --- locate frames -------------------------------------------------
candidatePaths = { ...
    'D:\Jordan''s Thesis\cascade\adc_samples\data', ...
    fullfile(fileparts(mfilename('fullpath')), '..', '..', '..', 'Jordan''s Thesis', 'cascade', 'adc_samples', 'data'), ...
    fullfile(fileparts(mfilename('fullpath')), '..', '..', 'Jordan''s Thesis', 'cascade', 'adc_samples', 'data'), ...
    'C:\Users\mohin\Downloads\12_21_2020_ec_hallways_run4\12_21_2020_ec_hallways_run4\cascade\adc_samples\data' ...
};

dataDir = '';
for i = 1:length(candidatePaths)
    if exist(candidatePaths{i}, 'dir')
        files = dir(fullfile(candidatePaths{i}, 'frame_*.bin'));
        if ~isempty(files)
            dataDir = candidatePaths{i};
            listing = files;
            break;
        end
    end
end

if isempty(dataDir)
    error('play_coloradar_video:noFrames', 'No frame_<N>.bin found in candidate directories.');
end
nums = zeros(numel(listing), 1);
for k = 1:numel(listing)
    tok = regexp(listing(k).name, 'frame_(\d+)\.bin', 'tokens', 'once');
    nums(k) = str2double(tok{1});
end
[nums, ord] = sort(nums);
listing = listing(ord);

if isempty(FRAME_RANGE)
    frameIdx = nums;
else
    frameIdx = intersect(FRAME_RANGE(:), nums);
end
if isempty(frameIdx)
    error('play_coloradar_video:noMatch', 'No frames matched FRAME_RANGE.');
end
nFrames = numel(frameIdx);
fprintf('Playing %d frames (frame %d to %d) from %s\n', ...
    nFrames, frameIdx(1), frameIdx(end), dataDir);

% Load timestamps if available (for the title clock)
tsFile = fullfile(fileparts(dataDir), 'timestamps.txt');
if exist(tsFile, 'file') == 2
    tstamps = readmatrix(tsFile);
    if numel(tstamps) >= max(frameIdx) + 1
        haveTimestamps = true;
    else
        haveTimestamps = false;
        warning('timestamps.txt has fewer entries than frames; ignoring.');
    end
else
    haveTimestamps = false;
end

%% --- bootstrap: load frame 0 to size the axes / pre-allocate -------
fprintf('Initialising from first frame...\n');
optsRD = struct('txSelect', 1:12, 'removeDC', true);
optsRA = struct('txSelect', AZ_TX_SELECT, 'removeDC', true);
firstFile = fullfile(dataDir, sprintf('frame_%d.bin', frameIdx(1)));
[cubeRD0, cfgRD] = loadColoRadarFrame(firstFile, optsRD);
[cubeRA0, cfgRA] = loadColoRadarFrame(firstFile, optsRA);

nRangeKeep = floor(cfgRD.numSamples / 2);
rangeRes   = 3e8 / (2 * cfgRD.bandWidth);
rangeAxis  = (0:nRangeKeep-1) * rangeRes;
keepRange  = rangeAxis <= RANGE_MAX_PLOT;
rangeAxisKept = rangeAxis(keepRange);

velAxisShifted = ((0:cfgRD.numRamps-1) - floor(cfgRD.numRamps/2)) ...
                  * (1 / cfgRD.PRI / cfgRD.numRamps) * cfgRD.lambda / 2;
nAzBins = cfgRA.numRxChannels * AZ_ZEROPAD;
azBins  = ((0:nAzBins-1) - floor(nAzBins/2)) / nAzBins;   % normalised spatial freq
azAngleDeg = asind(2 * azBins);                            % d = lambda/2

% Waterfall buffer
wfBuffer = nan(sum(keepRange), WATERFALL_LEN);
wfFrameIds = nan(1, WATERFALL_LEN);

%% --- auto colour limits from the first frame -----------------------
% So the user doesn't have to guess at dBFS levels. We base them on the
% true data range and pad a little; user-supplied limits override.
[autoRD, autoRA, autoWF] = autoFitLimits(firstFile, optsRD, optsRA, ...
                                         cfgRD, cfgRA, nRangeKeep, keepRange, nAzBins);
if isempty(DB_LIMITS_RD); DB_LIMITS_RD = autoRD; end
if isempty(DB_LIMITS_RA); DB_LIMITS_RA = autoRA; end
if isempty(DB_LIMITS_WF); DB_LIMITS_WF = autoWF; end
fprintf('Auto colour limits: RD %s   RA %s   WF %s\n', ...
    mat2str(DB_LIMITS_RD,3), mat2str(DB_LIMITS_RA,3), mat2str(DB_LIMITS_WF,3));

%% --- figure layout -------------------------------------------------
hFig = figure('Name', 'ColoRadar Frame Player', 'NumberTitle', 'off', ...
              'Color', 'w', 'Position', [80 80 1480 760]);
tl = tiledlayout(hFig, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

% (1) Range-Doppler
axRD = nexttile(tl, 1);
hImgRD = imagesc(axRD, velAxisShifted, rangeAxisKept, nan(sum(keepRange), cfgRD.numRamps));
axis(axRD, 'xy'); colormap(axRD, turbo); colorbar(axRD); caxis(axRD, DB_LIMITS_RD);
xlabel(axRD, 'Velocity (m/s)'); ylabel(axRD, 'Range (m)');
title(axRD, 'Range-Doppler (all 12 TX, TDM stripes expected)');

% (2) Range-Azimuth (top-down birdseye)
axRA = nexttile(tl, 2);
hImgRA = imagesc(axRA, azAngleDeg, rangeAxisKept, nan(sum(keepRange), nAzBins));
axis(axRA, 'xy'); colormap(axRA, turbo); colorbar(axRA); caxis(axRA, DB_LIMITS_RA);
xlim(axRA, [-60 60]);
xlabel(axRA, 'Azimuth angle (deg)'); ylabel(axRA, 'Range (m)');
title(axRA, sprintf('Range-Azimuth top-down (TX %d, 16 RX ULA)', AZ_TX_SELECT));

% (3) Range-time waterfall (spans bottom row)
axWF = nexttile(tl, 3, [1 2]);
hImgWF = imagesc(axWF, 1:WATERFALL_LEN, rangeAxisKept, wfBuffer);
axis(axWF, 'xy'); colormap(axWF, turbo); colorbar(axWF); caxis(axWF, DB_LIMITS_WF);
xlabel(axWF, sprintf('Frame index (most recent %d)', WATERFALL_LEN));
ylabel(axWF, 'Range (m)');
title(axWF, 'Range-time waterfall (NCI integrated over Doppler & RX)');

sgtitle(tl, 'ColoRadar cascade - press Ctrl+C or close window to stop', ...
        'FontWeight', 'bold');

drawnow;

%% --- playback loop -------------------------------------------------
frameDur = 1 / TARGET_FPS;
loopTimer = tic;
liveStart = tic;
nProcessed = 0;

for k = 1:nFrames
    if ~ishandle(hFig); break; end
    fi = frameIdx(k);
    fname = fullfile(dataDir, sprintf('frame_%d.bin', fi));

    %% (a) Load with both views (one disk read each, fast)
    cubeRD = loadColoRadarFrameQuiet(fname, optsRD);
    cubeRA = loadColoRadarFrameQuiet(fname, optsRA);

    %% (b) Range FFT on both cubes
    rdRange = computeRangeFFT(cubeRD);
    raRange = computeRangeFFT(cubeRA);

    %% (c) Range-Doppler image: Doppler FFT (Hanning) -> NCI over RX, in dB
    win = hanning(cfgRD.numRamps);
    rdDop = fft(rdRange .* reshape(win, 1, [], 1), [], 2);
    rdDop = fftshift(rdDop, 2);
    rdMag = sum(abs(rdDop).^2, 3);                    % [nRange x nDoppler]
    rdMag = rdMag(1:nRangeKeep, :);
    rdMag = rdMag(keepRange, :);
    rdDB  = 10 * log10(max(rdMag, eps) / fullScaleRefPowerCascade(cfgRD));

    %% (d) Range-Azimuth: angle FFT across RX antennas BEFORE squaring,
    % then integrate Doppler power. This gives a proper coherent angle
    % estimate per range-Doppler bin, summed (incoherently) over Doppler.
    raAz   = fftshift(fft(raRange, nAzBins, 3), 3);   % [nRange x nDop x nAz]
    raMag  = sum(abs(raAz).^2, 2);                    % integrate over Doppler
    raMag  = squeeze(raMag);                          % [nRange x nAz]
    raMag  = raMag(1:nRangeKeep, :);
    raMag  = raMag(keepRange, :);
    raDB   = 10 * log10(max(raMag, eps) / fullScaleRefPowerCascade(cfgRA));

    %% (e) Waterfall: integrate NCI power over Doppler -> smooth range profile in dB
    col   = sum(rdMag, 2);                            % [nRange x 1]
    colDB = 10 * log10(max(col, eps) / fullScaleRefPowerCascade(cfgRD));
    % Scroll the waterfall buffer one column to the left, append new
    wfBuffer(:, 1:end-1)   = wfBuffer(:, 2:end);
    wfBuffer(:, end)       = colDB;
    wfFrameIds(1:end-1)    = wfFrameIds(2:end);
    wfFrameIds(end)        = fi;

    %% (f) Push to plots
    set(hImgRD, 'CData', rdDB);
    set(hImgRA, 'CData', raDB);
    set(hImgWF, 'CData', wfBuffer);

    % Title clock
    if haveTimestamps
        relT = tstamps(fi + 1) - tstamps(frameIdx(1) + 1);
        titleStr = sprintf('Frame %d / %d   (t = %6.2f s   playback %4.1f fps)', ...
            fi, frameIdx(end), relT, nProcessed / max(toc(liveStart), eps));
    else
        titleStr = sprintf('Frame %d / %d   (playback %4.1f fps)', ...
            fi, frameIdx(end), nProcessed / max(toc(liveStart), eps));
    end
    sgtitle(tl, titleStr, 'FontWeight', 'bold');

    drawnow limitrate;

    % FPS cap (wait remainder of this frame's budget)
    nProcessed = nProcessed + 1;
    elapsed = toc(loopTimer);
    waitFor = frameDur - elapsed;
    if waitFor > 0
        pause(waitFor);
    end
    loopTimer = tic;
end

fprintf('Done. %d frames played in %.1f s (avg %.1f fps).\n', ...
    nProcessed, toc(liveStart), nProcessed / max(toc(liveStart), eps));

%% ======================================================================
function [lRD, lRA, lWF] = autoFitLimits(firstFile, optsRD, optsRA, ...
                                         cfgRD, cfgRA, nRangeKeep, keepRange, nAzBins)
% Compute one frame's worth of each view and pick colour limits as
% (5th percentile, 99th percentile) of the data, clipped to a sane range.
    cubeRD = loadColoRadarFrameQuiet(firstFile, optsRD);
    cubeRA = loadColoRadarFrameQuiet(firstFile, optsRA);

    win    = hanning(cfgRD.numRamps);
    rrRD   = computeRangeFFT(cubeRD);
    rdDop  = fft(rrRD .* reshape(win, 1, [], 1), [], 2);
    rdDop  = fftshift(rdDop, 2);
    rdMag  = sum(abs(rdDop).^2, 3);
    rdMag  = rdMag(1:nRangeKeep, :); rdMag = rdMag(keepRange, :);
    rdDB   = 10*log10(max(rdMag, eps) / fullScaleRefPowerCascade(cfgRD));
    lRD    = pickLims(rdDB);

    rrRA   = computeRangeFFT(cubeRA);
    raAz   = fftshift(fft(rrRA, nAzBins, 3), 3);
    raMag  = squeeze(sum(abs(raAz).^2, 2));
    raMag  = raMag(1:nRangeKeep, :); raMag = raMag(keepRange, :);
    raDB   = 10*log10(max(raMag, eps) / fullScaleRefPowerCascade(cfgRA));
    lRA    = pickLims(raDB);

    colDB  = 10*log10(max(sum(rdMag, 2), eps) / fullScaleRefPowerCascade(cfgRD));
    lWF    = pickLims(colDB);
end

function lims = pickLims(x)
    p = prctile(x(isfinite(x)), [5 99]);
    lims = [floor(p(1)) ceil(p(2))];
    if diff(lims) < 20; lims(2) = lims(1) + 30; end   % keep at least 30 dB range
end

function cube = loadColoRadarFrameQuiet(fname, opts)
% Wrapper around loadColoRadarFrame that swallows the per-frame stdout.
    evalc('cube = loadColoRadarFrame(fname, opts);');
end

function P = fullScaleRefPowerCascade(cfg)
% Same idea as computeFullScaleRefPower but lightweight (we only need the
% same 0 dBFS reference for the display, not the full Kiem normalisation).
% Use the integer-codes definition: peak NCI power if every sample were +/- 2^(b-1)-1.
    maxADCVal = 2^(cfg.bitWidth - 1) - 1;
    hannR = hanning(cfg.numSamples);
    hannD = hanning(cfg.numRamps);
    peakR = maxADCVal * sum(hannR) / cfg.numSamples;
    peakD = peakR * sum(hannD) / cfg.numRamps;
    P = cfg.numRxChannels * peakD^2;
end

function out = computeRangeFFT(cube)
% Light range FFT for visualisation only: Hanning window, FFT, keep
% positive-range half. Operates on the complex cube directly (no Kiem-style
% preprocessing because we are not doing any quantisation here).
    [N, M, ~] = size(cube);
    w = hanning(N);
    out = fft(cube .* w, [], 1) / N;
    out = out(1:N/2, :, :);
end
