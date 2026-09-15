%% LPC_PER_FRAME_CR  Per-frame MATLAB LPC+Huffman compression ratio (Test 2.3 support).
%
%  Mirrors drhe_per_frame_cr.m. Runs the identical MATLAB pipeline
%  (loadColoRadarFrame -> preprocessing -> rangeFFT -> compress_fx16) and then
%  compresses ONLY the first NRX_KEEP RX channels, which is what
%  export_frames_for_vitis.m writes into coloradar_multiframe.bin.
%
%  It reports three compression ratios per frame:
%    CR_matlab      - compress_lpc_huffman as written, full double-precision
%                     coefficients used for prediction
%    CR_quantised   - the same, but with a1/a2 first rounded to the 16-bit
%                     fixed-point formats the HLS uses (a1: 2 int bits,
%                     a2: 1 int bit). This is the like-for-like reference for
%                     the Vitis result.
%    CR_pad_frame   - CR_quantised after padding the bitstream out to whole
%                     256-bit AXI-Stream packets.
%
%  The distinction matters: compress_lpc_huffman charges 16 bits per
%  coefficient in its overhead term but predicts with 64-bit ones, so it is not
%  self-consistent. The quantised column is what a real 16-bit implementation
%  can actually achieve.
%
%  Output: lpc_per_frame_cr.csv

clear; clc;

%% ============ CONFIGURATION ==========================================
MAX_FRAMES  = 50;
if ~isempty(getenv('DRHE_MAX_FRAMES'))
    MAX_FRAMES = str2double(getenv('DRHE_MAX_FRAMES'));
end
TX_SELECT   = 1:12;
NRX_KEEP    = 4;
REMOVE_DC   = true;
AXI_WIDTH   = 256;
OUT_CSV     = fullfile(fileparts(mfilename('fullpath')), 'lpc_per_frame_cr.csv');
% =====================================================================

simDir = fileparts(mfilename('fullpath'));
candidatePaths = { ...
    'D:\Jordan''s Thesis\cascade\adc_samples\data', ...
    fullfile(simDir, '..', '..', '..', 'Jordan''s Thesis', 'cascade', 'adc_samples', 'data'), ...
    fullfile(simDir, '..', '..', 'Jordan''s Thesis', 'cascade', 'adc_samples', 'data') };

dataDir = '';
for i = 1:numel(candidatePaths)
    if exist(candidatePaths{i}, 'dir') && ~isempty(dir(fullfile(candidatePaths{i}, 'frame_*.bin')))
        dataDir = candidatePaths{i}; break;
    end
end
if isempty(dataDir), error('No frame files found.'); end

numFrames = min(MAX_FRAMES, numel(dir(fullfile(dataDir, 'frame_*.bin'))));

fprintf('================================================================\n');
fprintf('  MATLAB PER-FRAME LPC+HUFFMAN COMPRESSION RATIO\n');
fprintf('  Frames: %d   RX channels used: %d (matching Vitis export)\n', numFrames, NRX_KEEP);
fprintf('================================================================\n');

opts = struct('txSelect', TX_SELECT, 'removeDC', REMOVE_DC, 'fx16EffectiveBits', 16);
hl   = [4,3,2,2,2,5,6,7,8,9,10,11,14,14,13,12];

CR_matlab    = nan(numFrames,1);
CR_quantised = nan(numFrames,1);
CR_pad_frame = nan(numFrames,1);
bits_q       = nan(numFrames,1);
inputBits    = nan(numFrames,1);
overheadBits = nan(numFrames,1);

for f = 0:numFrames-1
    binFile = fullfile(dataDir, sprintf('frame_%d.bin', f));
    if exist(binFile,'file') ~= 2, continue; end

    evalc('[cube, config, ~] = loadColoRadarFrame(binFile, opts);');
    rangeFFTData = rangeFFT(preprocessing(cube, config), config);
    fx16 = compress_fx16(rangeFFTData, config);

    nRxUse = min(NRX_KEEP, size(fx16.real_part,3));
    R = double(fx16.real_part(:,:,1:nRxUse));
    I = double(fx16.imag_part(:,:,1:nRxUse));
    [nB, nR, nC] = size(R);

    bD = 0; bQ = 0;
    for c = 1:nC
        for n = 1:nB
            for part = 1:2
                if part == 1, sq = squeeze(R(n,:,c)); else, sq = squeeze(I(n,:,c)); end
                N = numel(sq);
                R0 = sum(sq.^2);
                R1 = sum(sq(1:N-1).*sq(2:N));
                R2 = sum(sq(1:N-2).*sq(3:N));
                det = R0^2 - R1^2;
                if det == 0
                    a1 = 0; a2 = 0;
                else
                    a1 = (R1*(R0-R2))/det;
                    a2 = (R0*R2 - R1^2)/det;
                    if abs(a2) >= 1 || abs(a1) >= (1-a2), a1 = 0; a2 = 0; end
                end
                % 16-bit fixed-point quantisation, matching lpc_a1_t / lpc_a2_t
                a1q = max(-2, min(2-2^-14, round(a1*2^14)/2^14));
                a2q = max(-1, min(1-2^-15, round(a2*2^15)/2^15));

                p1=0; p2=0; q1=0; q2=0;
                for m = 1:N
                    dD = mod(sq(m) - round(a1 *p1 + a2 *p2) + 32768, 65536) - 32768;
                    dQ = mod(sq(m) - round(a1q*q1 + a2q*q2) + 32768, 65536) - 32768;
                    bD = bD + huffbits(dD, hl);
                    bQ = bQ + huffbits(dQ, hl);
                    p2=p1; p1=sq(m);
                    q2=q1; q1=sq(m);
                end
            end
        end
    end

    ov = nB * nC * 4 * 16;          % 4 coefficients x 16 bits per (bin, channel)
    inB = nB * nR * nC * 2 * 16;

    inputBits(f+1)    = inB;
    overheadBits(f+1) = ov;
    bits_q(f+1)       = bQ + ov;
    CR_matlab(f+1)    = inB / (bD + ov);
    CR_quantised(f+1) = inB / (bQ + ov);
    CR_pad_frame(f+1) = inB / (ceil((bQ+ov)/AXI_WIDTH)*AXI_WIDTH);

    fprintf('  frame_%-3d  CR double=%.4f  quantised=%.4f  padded=%.4f  (bits %d -> %d, overhead %d)\n', ...
        f, CR_matlab(f+1), CR_quantised(f+1), CR_pad_frame(f+1), inB, bits_q(f+1), ov);
end

v = ~isnan(CR_matlab);
fprintf('\n================================================================\n');
fprintf('  SUMMARY (%d frames)\n', sum(v));
fprintf('================================================================\n');
fprintf('  Mean CR (double coefficients)   : %.5f\n', mean(CR_matlab(v)));
fprintf('  Mean CR (16-bit quantised)      : %.5f\n', mean(CR_quantised(v)));
fprintf('  Mean CR (quantised + AXI pad)   : %.5f\n', mean(CR_pad_frame(v)));
fprintf('  Quantisation cost               : %.4f%%\n', ...
    100*(mean(CR_matlab(v))-mean(CR_quantised(v)))/mean(CR_matlab(v)));
fprintf('  Coefficient overhead per frame  : %d bits (%.2f%% of compressed size)\n', ...
    overheadBits(1), 100*overheadBits(1)/mean(bits_q(v)));
fprintf('================================================================\n');

T = table((0:numFrames-1)', CR_matlab, CR_quantised, CR_pad_frame, inputBits, bits_q, overheadBits, ...
    'VariableNames', {'frame','CR_matlab','CR_quantised','CR_pad_frame','inputBits','totalBits_q','overheadBits'});
writetable(T, OUT_CSV);
fprintf('  Wrote %s\n', OUT_CSV);


function b = huffbits(v, hl)
    a = abs(v);
    if a == 0
        s4 = 0;
    else
        s4 = min(15, floor(log2(a)) + 1);
    end
    b = hl(s4+1) + s4;
end
