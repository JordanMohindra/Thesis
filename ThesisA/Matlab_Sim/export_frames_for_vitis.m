%% EXPORT_FRAMES_FOR_VITIS  Export FX16 Range-FFT data for the Vitis HLS testbench.
%  Loads N ColoRadar frames through the exact MATLAB pipeline
%  (loadColoRadarFrame -> preprocessing -> rangeFFT -> compress_fx16)
%  and writes the resulting int16 I/Q data to a single binary file.
%
%  This ensures the Vitis C-Simulation uses the EXACT same int16 values
%  that MATLAB's compress_drhe sees, eliminating floating-point DFT
%  discrepancies between Python and MATLAB FFT implementations.
%
%  Output file layout (little-endian):
%    Header:  [uint32 nFrames] [uint32 nSamples] [uint32 nRamps] [uint32 nRX]
%    Frame 0: for r=0..nRamps-1, s=0..nSamples-1, ch=0..nRX-1:
%               [int16 Re] [int16 Im]
%    Frame 1: ...
%    ...
%    Frame N-1: ...

clear; clc;

%% ============ CONFIGURATION ==========================================
MAX_FRAMES  = 50;            % Number of frames to export
TX_SELECT   = 1:12;          % TX antennas (1:12 = all, gives 192 ramps)
NRX_KEEP    = 4;             % Number of RX channels to keep (first N)
REMOVE_DC   = true;
OUTPUT_FILE = 'C:\Users\mohin\Vitis\hls_component\coloradar_multiframe.bin';
% =======================================================================

%% --- Locate frames ---------------------------------------------------
candidatePaths = { ...
    fullfile(fileparts(mfilename('fullpath')), '..', '..', 'Jordan''s Thesis', 'cascade', 'adc_samples', 'data'), ...
    'C:\Users\mohin\Downloads\12_21_2020_ec_hallways_run4\12_21_2020_ec_hallways_run4\cascade\adc_samples\data' ...
};

dataDir = '';
for i = 1:length(candidatePaths)
    if exist(candidatePaths{i}, 'dir')
        files = dir(fullfile(candidatePaths{i}, 'frame_*.bin'));
        if ~isempty(files)
            dataDir = candidatePaths{i};
            break;
        end
    end
end

if isempty(dataDir)
    error('No frame files found in candidate directories.');
end

numAvailable = length(dir(fullfile(dataDir, 'frame_*.bin')));
numFrames = min(MAX_FRAMES, numAvailable);

fprintf('================================================================\n');
fprintf('  EXPORT FRAMES FOR VITIS HLS TESTBENCH\n');
fprintf('  Exporting %d frames from %s\n', numFrames, dataDir);
fprintf('================================================================\n');

opts = struct('txSelect', TX_SELECT, 'removeDC', REMOVE_DC, 'fx16EffectiveBits', 16);

%% --- Open output file & write header ---------------------------------
fid = fopen(OUTPUT_FILE, 'w');
if fid == -1
    error('Could not open output file: %s', OUTPUT_FILE);
end

% We'll write the header after processing the first frame (to get dimensions)
headerWritten = false;
nSampOut = 0;
nRampsOut = 0;

for f = 0:numFrames-1
    binFile = fullfile(dataDir, sprintf('frame_%d.bin', f));
    if exist(binFile, 'file') ~= 2
        fprintf('  Skipping missing frame_%d.bin\n', f);
        continue;
    end

    fprintf('  Processing frame_%d.bin (%d/%d)... ', f, f+1, numFrames);

    % Load through exact MATLAB pipeline
    [cube, config, ~] = loadColoRadarFrame(binFile, opts);
    preprocessedData = preprocessing(cube, config);
    rangeFFTData     = rangeFFT(preprocessedData, config);

    % FX16 quantization (produces int16 real & imag)
    compressedFX16 = compress_fx16(rangeFFTData, config);

    realPart = compressedFX16.real_part;  % int16 [nSamples x nRamps x nRX]
    imagPart = compressedFX16.imag_part;  % int16 [nSamples x nRamps x nRX]

    [nSamp, nRamps, nRx] = size(realPart);
    nRxUse = min(NRX_KEEP, nRx);

    % Write header on first frame
    if ~headerWritten
        nSampOut = nSamp;
        nRampsOut = nRamps;
        fwrite(fid, uint32(numFrames), 'uint32');
        fwrite(fid, uint32(nSampOut), 'uint32');
        fwrite(fid, uint32(nRampsOut), 'uint32');
        fwrite(fid, uint32(nRxUse), 'uint32');
        headerWritten = true;
    end

    % Write frame data in testbench order: ramp -> sample -> channel -> (Re, Im)
    for r = 1:nRamps
        for s = 1:nSamp
            for ch = 1:nRxUse
                fwrite(fid, realPart(s, r, ch), 'int16');
                fwrite(fid, imagPart(s, r, ch), 'int16');
            end
        end
    end

    fprintf('Done.\n');
end

fclose(fid);

info = dir(OUTPUT_FILE);
fprintf('\n================================================================\n');
fprintf('  EXPORT COMPLETE\n');
fprintf('  Output: %s\n', OUTPUT_FILE);
fprintf('  Size  : %.2f MB (%d bytes)\n', info.bytes / 1024 / 1024, info.bytes);
fprintf('  Frames: %d  Samples: %d  Ramps: %d  RX: %d\n', numFrames, nSampOut, nRampsOut, nRxUse);
fprintf('================================================================\n');
