%% DRHE_PER_FRAME_CR  Per-frame MATLAB DRHE compression ratio (Test 2.3 support).
%
%  The 8-algorithm batch benchmark reports only global averages, and it runs
%  DRHE over all 16 RX channels. The Vitis testbench, by contrast, consumes
%  coloradar_multiframe.bin, which export_frames_for_vitis.m writes with only
%  the first NRX_KEEP (= 4) RX channels.
%
%  To compare MATLAB against Vitis frame-by-frame, both sides must see the
%  same data. This script therefore runs the identical MATLAB pipeline
%  (loadColoRadarFrame -> preprocessing -> rangeFFT -> compress_fx16) and then
%  compresses ONLY the first NRX_KEEP RX channels with compress_drhe.
%
%  It also reports the compression ratio the HLS implementation should achieve
%  once its bitstream is padded out to whole 256-bit AXI-Stream packets, under
%  two plausible flush policies, so the residual MATLAB-vs-Vitis difference can
%  be attributed rather than guessed at.
%
%  Output: drhe_per_frame_cr.csv

clear; clc;

%% ============ CONFIGURATION ==========================================
MAX_FRAMES  = 50;
if ~isempty(getenv('DRHE_MAX_FRAMES'))
    MAX_FRAMES = str2double(getenv('DRHE_MAX_FRAMES'));
end
TX_SELECT   = 1:12;
NRX_KEEP    = 4;             % must match export_frames_for_vitis.m
REMOVE_DC   = true;
AXI_WIDTH   = 256;           % bits per compressed AXI-Stream packet
OUT_CSV     = fullfile(fileparts(mfilename('fullpath')), 'drhe_per_frame_cr.csv');
% =====================================================================

simDir = fileparts(mfilename('fullpath'));
candidatePaths = { ...
    fullfile(simDir, '..', '..', '..', 'Jordan''s Thesis', 'cascade', 'adc_samples', 'data'), ...
    fullfile(simDir, '..', '..', 'Jordan''s Thesis', 'cascade', 'adc_samples', 'data') ...
};

dataDir = '';
for i = 1:numel(candidatePaths)
    if exist(candidatePaths{i}, 'dir') && ~isempty(dir(fullfile(candidatePaths{i}, 'frame_*.bin')))
        dataDir = candidatePaths{i};
        break;
    end
end
if isempty(dataDir)
    error('No frame files found in candidate directories.');
end

numAvailable = numel(dir(fullfile(dataDir, 'frame_*.bin')));
numFrames    = min(MAX_FRAMES, numAvailable);

fprintf('================================================================\n');
fprintf('  MATLAB PER-FRAME DRHE COMPRESSION RATIO\n');
fprintf('  Frames: %d   RX channels used: %d (matching Vitis export)\n', numFrames, NRX_KEEP);
fprintf('================================================================\n');

opts = struct('txSelect', TX_SELECT, 'removeDC', REMOVE_DC, 'fx16EffectiveBits', 16);

CR         = nan(numFrames, 1);
totalBits  = nan(numFrames, 1);
inputBits  = nan(numFrames, 1);
crPadFrame = nan(numFrames, 1);   % one 256-bit flush at end of frame
crPadRamp  = nan(numFrames, 1);   % one 256-bit flush at end of every ramp

for f = 0:numFrames-1
    binFile = fullfile(dataDir, sprintf('frame_%d.bin', f));
    if exist(binFile, 'file') ~= 2
        fprintf('  Skipping missing frame_%d.bin\n', f);
        continue;
    end

    evalc('[cube, config, ~] = loadColoRadarFrame(binFile, opts);');
    preprocessedData = preprocessing(cube, config);
    rangeFFTData     = rangeFFT(preprocessedData, config);
    fx16             = compress_fx16(rangeFFTData, config);

    % Restrict to the RX channels the Vitis testbench actually receives
    nRxUse = min(NRX_KEEP, size(fx16.real_part, 3));
    fxSub  = fx16;
    fxSub.real_part = fx16.real_part(:, :, 1:nRxUse);
    fxSub.imag_part = fx16.imag_part(:, :, 1:nRxUse);

    cfgSub = config;
    cfgSub.numRxChannels = nRxUse;

    drhe = compress_drhe(fxSub, cfgSub);

    [nBins, nRamps, ~] = size(fxSub.real_part);

    CR(f+1)        = drhe.CR;
    totalBits(f+1) = drhe.totalBits;
    inputBits(f+1) = drhe.inputBits;

    % Padding model A: bitstream flushed once at end of frame
    padA = ceil(drhe.totalBits / AXI_WIDTH) * AXI_WIDTH;
    crPadFrame(f+1) = drhe.inputBits / padA;

    % Padding model B: bitstream flushed at the end of every ramp
    padB = nRamps * ceil((drhe.totalBits / nRamps) / AXI_WIDTH) * AXI_WIDTH;
    crPadRamp(f+1) = drhe.inputBits / padB;

    fprintf('  frame_%-3d  CR=%.4f  bits %d -> %d   (CR pad/frame=%.4f  pad/ramp=%.4f)\n', ...
        f, CR(f+1), inputBits(f+1), totalBits(f+1), crPadFrame(f+1), crPadRamp(f+1));
end

valid = ~isnan(CR);

fprintf('\n================================================================\n');
fprintf('  SUMMARY (%d frames)\n', sum(valid));
fprintf('================================================================\n');
fprintf('  Mean CR (unpadded, MATLAB)      : %.4f\n', mean(CR(valid)));
fprintf('  Std  CR                         : %.4f\n', std(CR(valid)));
fprintf('  Min / Max CR                    : %.4f / %.4f\n', min(CR(valid)), max(CR(valid)));
fprintf('  Aggregate CR (sum in / sum out) : %.4f\n', sum(inputBits(valid)) / sum(totalBits(valid)));
fprintf('  Mean CR (256-bit pad per frame) : %.4f\n', mean(crPadFrame(valid)));
fprintf('  Mean CR (256-bit pad per ramp)  : %.4f\n', mean(crPadRamp(valid)));
fprintf('================================================================\n');

T = table((0:numFrames-1)', CR, inputBits, totalBits, crPadFrame, crPadRamp, ...
    'VariableNames', {'frame','CR_matlab','inputBits','totalBits','CR_pad_per_frame','CR_pad_per_ramp'});
writetable(T, OUT_CSV);
fprintf('  Wrote %s\n', OUT_CSV);
