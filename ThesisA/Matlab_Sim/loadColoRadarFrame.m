function [cube, config, axesInfo] = loadColoRadarFrame(binFile, opts)
% LOADCOLORADARFRAME Load one ColoRadar cascade frame_<N>.bin into a Matlab_Sim cube.
%
%   [cube, config, axesInfo] = loadColoRadarFrame(binFile, opts)
%
%   ColoRadar dataset (Kramer et al. 2021, arXiv:2103.04510) cascade format:
%       * TI MMWCAS-RF-EVM  (4 x AWR2243 cascaded)
%       * 16 RX, 12 TX TDM-MIMO, 16 chirp loops, 256 ADC samples per chirp
%       * Each complex sample is two contiguous int16 values (I, then Q)
%       * Index of one complex sample (s, c, r, t) in the int16 stream:
%             i = 2 * (s + Ns*(c + Nc*(r + t*Nr)))
%         i.e. layout slowest-to-fastest is [t, r, c, s].
%       * Resulting file size = 256*16*16*12*4 bytes = 3,145,728 bytes per frame.
%
%   The loader reshapes the file into a 3-D cube
%             cube : [numSamples x numRamps x numRxChannels]   (complex double)
%   matching the shape generateSyntheticADC.m produces, so runCompressionSim.m
%   accepts it directly as its 4th argument.
%
%   The 12 TX are flattened into the ramp axis in TDM-MIMO time order
%   (TX is the fastest-varying index inside each chirp loop):
%       ramp 0  = chirp 0,  TX 0
%       ramp 1  = chirp 0,  TX 1
%       ...
%       ramp 11 = chirp 0,  TX 11
%       ramp 12 = chirp 1,  TX 0
%       ...
%   so numRamps = numChirpLoops * numTx = 16 * 12 = 192 by default.
%
%   INPUTS
%     binFile - path to a frame_<N>.bin file (or [] to be prompted).
%     opts    - (optional) struct:
%         .txSelect     vector of TX indices to keep (default 1:12). E.g.
%                       set to 1 to use only one TX and get a 256x16x16 cube.
%         .removeDC     logical, subtract the per-ramp mean (DC / coupling
%                       term) per channel (default true).
%         .bitWidth     ADC bit width used for dBFS scaling and FX16 range
%                       (default 16, the int16 raw container; auto-detect
%                       sets it from the peak |sample|).
%         .autoBitWidth logical, replace bitWidth with the auto-detected
%                       smallest value that contains the peak |sample|
%                       (default false; keeping 16 matches Kiem's int16 path).
%         .fx16EffectiveBits  effective FX bits for the FX16 path
%                       (default 16 = no extra quantisation loss).
%         .sampRate     fast-time ADC sample rate (Hz, default 8e6 - the
%                       standard ColoRadar cascade setting from the public
%                       waveform_cfg.txt).
%         .bandwidth    chirp bandwidth (Hz, default 1.798e9 - standard
%                       ColoRadar cascade).
%         .chirpPeriod  TDM chirp-to-chirp interval (s, default 78.5e-6).
%         .fc           centre frequency (Hz, default 77e9).
%         .rangeMaxPlot range axis cap for plots, metres (default Inf).
%         .velMaxPlot   velocity axis cap for plots, m/s (default Inf).
%
%   OUTPUTS
%     cube     - complex double [numSamples x numRamps x numRxChannels]
%     config   - struct compatible with the Matlab_Sim pipeline
%     axesInfo - struct of physical plot axes for the *_real plotters
%
%   See also: loadRealRadarCube, runCompressionSim, main_simulation_coloradar.

    if nargin < 2 || isempty(opts); opts = struct(); end
    opts = setDefault(opts, 'txSelect',          1:12);
    opts = setDefault(opts, 'removeDC',          true);
    opts = setDefault(opts, 'bitWidth',          16);
    opts = setDefault(opts, 'autoBitWidth',      false);
    opts = setDefault(opts, 'fx16EffectiveBits', 16);
    opts = setDefault(opts, 'sampRate',          8e6);
    opts = setDefault(opts, 'bandwidth',         1.798e9);
    opts = setDefault(opts, 'chirpPeriod',       78.5e-6);
    opts = setDefault(opts, 'fc',                77e9);
    opts = setDefault(opts, 'rangeMaxPlot',      inf);
    opts = setDefault(opts, 'velMaxPlot',        inf);

    %% --- file selection ---------------------------------------------------
    if nargin < 1 || isempty(binFile)
        [fn, fp] = uigetfile({'*.bin'}, 'Select a ColoRadar cascade frame_<N>.bin');
        if isequal(fn, 0)
            error('loadColoRadarFrame:cancelled', 'Frame selection cancelled.');
        end
        binFile = fullfile(fp, fn);
    end
    if exist(binFile, 'file') ~= 2
        error('loadColoRadarFrame:notFound', 'File not found: %s', binFile);
    end

    %% --- fixed cascade dimensions ----------------------------------------
    Ns = 256;        % samples per chirp
    Nc = 16;         % chirp loops per frame
    Nr = 16;         % RX channels (4 chips x 4 RX)
    Nt = 12;         % TX antennas (4 chips x 3 TX)
    expectedBytes = 2 * (Ns * Nc * Nr * Nt) * 2;   % complex int16 = 4 B/sample
    info = dir(binFile);
    if info.bytes ~= expectedBytes
        error('loadColoRadarFrame:wrongSize', ...
            'File size %d B does not match expected %d B for %dx%dx%dx%d complex int16.', ...
            info.bytes, expectedBytes, Ns, Nc, Nr, Nt);
    end

    %% --- read file -------------------------------------------------------
    fid = fopen(binFile, 'r');
    if fid == -1
        error('loadColoRadarFrame:openFail', 'Could not open %s', binFile);
    end
    rawInt = fread(fid, inf, 'int16=>int16');
    fclose(fid);

    I = double(rawInt(1:2:end));
    Q = double(rawInt(2:2:end));
    complexSamples = complex(I, Q);

    cube4D = reshape(complexSamples, [Ns, Nc, Nr, Nt]);
    %                                  ^ fastest dim (samples)
    %                                       ^ chirp loop
    %                                            ^ RX channel
    %                                                ^ TX antenna (slowest dim)

    %% --- TX subset + flatten chirp loops x TX -> ramp axis -------------
    txKeep = opts.txSelect;
    if ~isvector(txKeep) || any(txKeep < 1) || any(txKeep > Nt)
        error('loadColoRadarFrame:badTxSelect', 'txSelect must be a vector with values in 1:%d.', Nt);
    end
    cube4D = cube4D(:, :, :, txKeep);
    NtKeep = numel(txKeep);

    % TDM-MIMO time order: for chirp loop c, TX 0..NtKeep-1 fire in sequence
    % BEFORE the next chirp loop starts. The flattened ramp index = c*NtKeep + t,
    % i.e. TX is the fastest-varying index. permute to [Ns, Nt, Nc, Nr] then
    % reshape collapses the [Nt Nc] block into the ramp dim in that exact order.
    cubeTDM = permute(cube4D, [1 4 2 3]);    % [Ns, NtKeep, Nc, Nr]
    cube    = reshape(cubeTDM, [Ns, NtKeep*Nc, Nr]);

    if opts.removeDC
        cube = cube - mean(cube, 1);
    end

    [nSamp, nRamps, nCh] = size(cube);

    %% --- bit-width / dBFS reference --------------------------------------
    peakAbs = max([abs(real(cube(:))); abs(imag(cube(:))); 1]);
    autoBW  = max(8, ceil(log2(peakAbs + 1)) + 1);
    if opts.autoBitWidth
        bitWidth = autoBW;
    else
        bitWidth = opts.bitWidth;
    end

    %% --- radar parameters -----------------------------------------------
    lambda   = 3e8 / opts.fc;
    sweepT   = opts.chirpPeriod;
    PRI      = sweepT * NtKeep;          % per-TX revisit period
    rangeRes = 3e8 / (2 * opts.bandwidth);
    rangeMax = rangeRes * nSamp / 2;
    velMax   = lambda / (4 * PRI);       % Nyquist velocity (TX-PRI based)

    config = struct();
    config.numSamples       = nSamp;
    config.numRamps         = nRamps;
    config.numRxChannels    = nCh;
    config.bitWidth         = bitWidth;
    config.fx16EffectiveBits = opts.fx16EffectiveBits;
    config.realData         = true;
    config.complexInput     = true;
    config.sampRate         = opts.sampRate;
    config.bandWidth        = opts.bandwidth;
    config.sweepTime        = sweepT;
    config.fc               = opts.fc;
    config.lambda           = lambda;
    config.PRI              = PRI;
    config.PRF              = 1 / PRI;
    config.rangeMax         = rangeMax;
    config.velMax           = velMax;
    config.nTx              = NtKeep;

    %% --- physical plot axes ---------------------------------------------
    nHalf = nSamp / 2;
    rangeAxis = (0:nHalf-1) * rangeRes;
    k = (0:nRamps-1) - floor(nRamps/2);
    velAxis = k * (1 / PRI / nRamps) * lambda / 2;

    axesInfo = struct();
    axesInfo.realData     = true;
    axesInfo.rangeAxis    = rangeAxis(:)';
    axesInfo.velAxis      = velAxis(:)';
    axesInfo.rangeMaxPlot = min(opts.rangeMaxPlot, rangeMax);
    axesInfo.velMaxPlot   = min(opts.velMaxPlot,   velMax);
    axesInfo.bgSubtract   = false;
    axesInfo.labels       = compose('rx%02d', 1:nCh);

    %% --- report ----------------------------------------------------------
    fprintf('--- loadColoRadarFrame ---\n');
    fprintf('  file       : %s\n', binFile);
    fprintf('  cube       : %d samples x %d ramps x %d RX  (TX kept: %s)\n', ...
        nSamp, nRamps, nCh, mat2str(txKeep));
    fprintf('  peak |sample| = %g (auto bitWidth=%d, using=%d)\n', peakAbs, autoBW, bitWidth);
    fprintf('  BW=%.2f GHz  fc=%.1f GHz  Tc=%.1f us  PRI=%.1f us\n', ...
        opts.bandwidth/1e9, opts.fc/1e9, sweepT*1e6, PRI*1e6);
    fprintf('  Range_max=%.2f m   Nyquist velocity=+/-%.3f m/s\n', rangeMax, velMax);
end

%% ======================================================================== %%
function opts = setDefault(opts, field, val)
    if ~isfield(opts, field)
        opts.(field) = val;
    end
end
