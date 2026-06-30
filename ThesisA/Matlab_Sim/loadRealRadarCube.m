function [cube, config, axesInfo] = loadRealRadarCube(tgtFile, bgFile, opts)
% LOADREALRADARCUBE Turn a real Ancortek FMCW capture into a Matlab_Sim ADC cube.
%
%   [cube, config, axesInfo] = loadRealRadarCube(tgtFile, bgFile, opts)
%
%   Reads a recorded Ancortek 2Tx/4Rx FMCW binary (the same files
%   read_radar_data_fmcw.m consumes), demultiplexes every valid Tx/Rx I/Q
%   stream and assembles a complex data cube
%
%        cube : [numSamples x numRamps x numRxChannels]   (complex double)
%
%   shaped EXACTLY like the synthetic cube produced by generateSyntheticADC.m.
%   This lets a real capture be pushed through the unchanged Kiem compression
%   workflow (preprocessing -> rangeFFT -> secondStageProcessing -> FP16/FX16/
%   DRHE) and plotted with the same plotProcessingStages / plotCompressionComparison
%   routines (so you get the 3D range-Doppler "cloud" on real data).
%
%   INPUTS
%     tgtFile - path to the TARGET capture (.bin or .mat). If omitted/empty a
%               file picker is shown.
%     bgFile  - path to the BACKGROUND capture (scene with no target). If
%               omitted/empty a picker is shown; pick Cancel to skip background
%               subtraction entirely.
%     opts    - (optional) struct:
%         .bgSubtract   logical, subtract the averaged background sweep from
%                       every target ramp (default: true when a background is
%                       available, false otherwise). Background subtraction is a
%                       LINEAR operation in the raw ADC domain, so it commutes
%                       with the range FFT and is identical to subtracting the
%                       background range profile. It removes the static clutter
%                       that reveals the moving target -- but that same clutter
%                       is the correlated energy DRHE compresses best, so turning
%                       this on will LOWER the measured DRHE compression ratio.
%         .removeDC     logical, subtract the per-sweep mean (DC / coupling
%                       term) from every channel before anything else
%                       (default true). Real ADC samples carry a large DC
%                       offset that would otherwise dominate range bin 0.
%         .maxRamps     cap the number of target ramps used (default [] = all).
%         .bitWidth     ADC bit width used for dBFS scaling and FX16 range
%                       (default [] = auto-detect from the data so the capture
%                       sits near full-scale).
%         .fx16EffectiveBits  effective FX16 bits for the fixed-point path
%                       (default 16 = no extra quantisation loss).
%         .rangeMaxPlot range axis cap for the plots, metres (default 2).
%         .velMaxPlot   velocity axis cap for the plots, m/s (default [] =
%                       radar Nyquist velocity).
%
%   OUTPUTS
%     cube     - complex double [numSamples x numRamps x numRxChannels]
%     config   - struct compatible with the Matlab_Sim pipeline plus real-radar
%                metadata (.sampRate, .bandWidth, .sweepTime, .fc, .lambda,
%                .rangeMax, .velMax, .nTx, .realData, .complexInput, ...).
%     axesInfo - struct of physical plot axes for the *_real plotters:
%                .realData, .rangeAxis (m), .velAxis (m/s), .rangeMaxPlot,
%                .velMaxPlot, .labels, .bgSubtract.
%
%   See also: main_simulation_real, read_radar_data_fmcw, runCompressionSim.

    if nargin < 3 || isempty(opts); opts = struct(); end
    opts = setDefault(opts, 'removeDC', true);
    opts = setDefault(opts, 'maxRamps', []);
    opts = setDefault(opts, 'bitWidth', []);
    opts = setDefault(opts, 'fx16EffectiveBits', 16);
    opts = setDefault(opts, 'rangeMaxPlot', 2);
    opts = setDefault(opts, 'velMaxPlot', []);

    %% --- file selection ---------------------------------------------------
    if nargin < 1 || isempty(tgtFile)
        [tn, tp] = uigetfile({'*.bin';'*.mat'}, 'Select the TARGET radar data file');
        if isequal(tn, 0); error('loadRealRadarCube:cancelled', 'Target selection cancelled.'); end
        tgtFile = fullfile(tp, tn);
    end
    haveBg = true;
    if nargin < 2
        [bn, bp] = uigetfile({'*.bin';'*.mat'}, 'Select the BACKGROUND file (Cancel to skip)', fileparts(tgtFile));
        if isequal(bn, 0); haveBg = false; bgFile = ''; else; bgFile = fullfile(bp, bn); end
    elseif isempty(bgFile)
        haveBg = false;
    end
    opts = setDefault(opts, 'bgSubtract', haveBg);
    if opts.bgSubtract && ~haveBg
        warning('loadRealRadarCube:noBackground', 'bgSubtract requested but no background file given; disabling.');
        opts.bgSubtract = false;
    end

    %% --- read + demux -----------------------------------------------------
    tgt = readAncortekBin(tgtFile);
    handles = struct('NTS', tgt.nSamp, 'Num_Rx', tgt.nRx, 'Num_Tx', tgt.nTx);

    [cube, labels] = buildCube(tgt.ADCsamples, handles, tgt.nSamp);
    if isempty(cube)
        error('loadRealRadarCube:noChannels', 'No valid Tx/Rx channels recovered from %s.', tgtFile);
    end

    if opts.removeDC
        cube = cube - mean(cube, 1);    % per-sweep, per-channel DC removal
    end

    if ~isempty(opts.maxRamps) && size(cube, 2) > opts.maxRamps
        cube = cube(:, 1:opts.maxRamps, :);
    end

    %% --- background subtraction ------------------------------------------
    if opts.bgSubtract
        bg = readAncortekBin(bgFile);
        bgHandles = struct('NTS', bg.nSamp, 'Num_Rx', bg.nRx, 'Num_Tx', bg.nTx);
        [bgCube, bgLabels] = buildCube(bg.ADCsamples, bgHandles, bg.nSamp);
        if opts.removeDC
            bgCube = bgCube - mean(bgCube, 1);
        end
        % Average background over its sweeps -> one clutter template per channel,
        % then subtract it from every target ramp of the matching channel.
        for c = 1:numel(labels)
            bc = find(strcmp(bgLabels, labels{c}), 1);
            if ~isempty(bc)
                template = mean(bgCube(:, :, bc), 2);          % [nSamp x 1]
                cube(:, :, c) = cube(:, :, c) - template;      % broadcast over ramps
            else
                warning('loadRealRadarCube:bgChannelMissing', ...
                    'Background has no channel %s; left un-subtracted.', labels{c});
            end
        end
    end

    [nSamp, nRamps, nCh] = size(cube);

    %% --- radar parameters / config ---------------------------------------
    bandWidth = tgt.fStop - tgt.fStart;          % Hz
    fc        = (tgt.fStart + tgt.fStop) / 2;    % Hz
    lambda    = 3e8 / fc;                         % m
    sweepTime = tgt.sTime;                        % s
    sampRate  = nSamp / sweepTime;               % Hz (fast-time ADC rate)
    PRF       = 1 / sweepTime / tgt.nTx;         % Hz
    rangeMax  = 3e8 / (2 * bandWidth) * nSamp / 2;
    velMax    = PRF / 2 * lambda / 2;

    if isempty(opts.bitWidth)
        peakAbs  = max([abs(real(cube(:))); abs(imag(cube(:))); 1]);  % scalar
        bitWidth = max(8, ceil(log2(peakAbs + 1)) + 1);     % +1 for sign
    else
        bitWidth = opts.bitWidth;
    end

    config = struct();
    config.numSamples       = nSamp;
    config.numRamps         = nRamps;
    config.numRxChannels    = nCh;
    config.bitWidth         = bitWidth;
    config.fx16EffectiveBits = opts.fx16EffectiveBits;
    config.realData         = true;
    config.complexInput     = true;
    % real-radar metadata (for axes / reporting)
    config.sampRate  = sampRate;
    config.bandWidth = bandWidth;
    config.sweepTime = sweepTime;
    config.fStart    = tgt.fStart;
    config.fStop     = tgt.fStop;
    config.fc        = fc;
    config.lambda    = lambda;
    config.PRF       = PRF;
    config.rangeMax  = rangeMax;
    config.velMax    = velMax;
    config.nTx       = tgt.nTx;
    config.channelLabels = labels;

    %% --- physical plot axes ----------------------------------------------
    nHalf = nSamp / 2;                                   % range bins kept by rangeFFT
    rangeAxis = (0:nHalf-1) * (sampRate / nSamp) * 3e8 * sweepTime / (2 * bandWidth);
    % Doppler bins after secondStageProcessing are unshifted (0..nRamps-1); the
    % plotters fftshift for display, so build the matching shifted velocity axis.
    k = (0:nRamps-1) - floor(nRamps/2);
    velAxis = k * (PRF / nRamps) * lambda / 2;

    rangeMaxPlot = min(opts.rangeMaxPlot, rangeMax);
    if isempty(opts.velMaxPlot); velMaxPlot = velMax; else; velMaxPlot = opts.velMaxPlot; end

    axesInfo = struct();
    axesInfo.realData     = true;
    axesInfo.rangeAxis    = rangeAxis(:)';
    axesInfo.velAxis      = velAxis(:)';
    axesInfo.rangeMaxPlot = rangeMaxPlot;
    axesInfo.velMaxPlot   = velMaxPlot;
    axesInfo.bgSubtract   = opts.bgSubtract;
    axesInfo.labels       = labels;

    %% --- report -----------------------------------------------------------
    fprintf('--- loadRealRadarCube ---\n');
    fprintf('  target     : %s\n', tgtFile);
    if opts.bgSubtract; fprintf('  background : %s (subtracted)\n', bgFile);
    elseif haveBg;      fprintf('  background : %s (available, NOT subtracted)\n', bgFile);
    else;               fprintf('  background : none\n'); end
    fprintf('  cube       : %d samples x %d ramps x %d channels {%s}\n', ...
        nSamp, nRamps, nCh, strjoin(labels, ', '));
    fprintf('  bitWidth   : %d (%s)\n', bitWidth, ternary(isempty(opts.bitWidth), 'auto', 'forced'));
    fprintf('  BW=%.1f MHz  fc=%.2f GHz  sweep=%.1f us  PRF=%.1f Hz\n', ...
        bandWidth/1e6, fc/1e9, sweepTime*1e6, PRF);
    fprintf('  Range_max=%.2f m   Nyquist velocity=+/-%.3f m/s\n', rangeMax, velMax);
end

%% ======================================================================== %%
function [cube, labels] = buildCube(ADCsamples, handles, nSamp)
% Demux every valid Tx/Rx complex stream and reshape into [nSamp x nSweeps x nCh].
    [chans, labels] = getAncortekChannels(ADCsamples, handles);
    if isempty(chans); cube = []; return; end
    % trim every channel to a common whole number of sweeps
    nSw = inf;
    for i = 1:numel(chans)
        nSw = min(nSw, floor(numel(chans{i}) / nSamp));
    end
    nSw = max(nSw, 0);
    if nSw < 1; cube = []; return; end
    cube = zeros(nSamp, nSw, numel(chans));
    for i = 1:numel(chans)
        v = chans{i}(1:nSw*nSamp);
        cube(:, :, i) = reshape(v, nSamp, nSw);
    end
end

%% ======================================================================== %%
function opts = setDefault(opts, field, val)
% Set opts.(field)=val only when the field is absent. An explicit value
% (including logical false) supplied by the caller is always preserved.
    if ~isfield(opts, field)
        opts.(field) = val;
    end
end

%% ======================================================================== %%
function out = ternary(cond, a, b)
    if cond; out = a; else; out = b; end
end
