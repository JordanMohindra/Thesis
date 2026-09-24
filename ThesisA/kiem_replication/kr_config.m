function cfg = kr_config(scenario)
%KR_CONFIG  Configuration for the replication of Kiem's MATLAB simulation.
%
%   cfg = kr_config('sim')      Kiem Table 3.2: the simulated scene he used
%                               (1 MMIC, 1 TX, 4 RX, 1024 samples, 512 ramps,
%                               14-bit ADC, 5 targets, -75 dBFS noise after NCI)
%   cfg = kr_config('usecase')  Kiem Table 3.3 dimensions (1024 x 1024, 12-bit)
%                               with the Table 3.2 targets
%
%   Every value below is taken from Kiem's thesis (section in brackets) unless
%   the comment says ASSUMPTION. Assumptions are needed only where his text
%   does not give a value; each one can be changed here.
%
%   This folder is self-contained: it does not call anything in Matlab_Sim.

if nargin < 1, scenario = 'sim'; end

switch lower(scenario)
    case 'sim'                       % Kiem Table 3.2
        cfg.numSamples = 1024;
        cfg.numRamps   = 512;
        cfg.numRx      = 4;
        cfg.bitWidth   = 14;
    case 'usecase'                   % Kiem Table 3.3 (12-bit, 1024 ramps)
        cfg.numSamples = 1024;
        cfg.numRamps   = 1024;
        cfg.numRx      = 4;
        cfg.bitWidth   = 12;
    otherwise
        error('kr_config: unknown scenario "%s"', scenario);
end
cfg.scenario = lower(scenario);

% --- Radar front end ------------------------------------------------------
cfg.numMMIC = 1;                     % [Table 3.2]
cfg.numTx   = 1;                     % one MMIC, SIMO: one transmitter [2.1.1]
cfg.tdmTx   = 1;                     % number of TX interleaved along the ramp
                                     % axis. 1 = Kiem's radar. Set to 12 only in
                                     % kr_tdm_experiment.m to mimic ColoRadar.

% --- Scene [Table 3.2] ----------------------------------------------------
cfg.targets.rangeBin   = [100 150 150 200 400];   % range-FFT bin (of N/2)
cfg.targets.dopplerBin = [ 50  50 100 200 250];   % Doppler bin (of numRamps)
cfg.targets.amplitude  = [0.8 0.3 0.4 0.5 0.7];   % fraction of ADC full scale
% ASSUMPTION: Kiem gives no arrival angles. Fixed, distinct angles are used so
% the four RX channels differ (uniform linear array, lambda/2 spacing).
cfg.targets.angleDeg   = [-30 -10 0 15 40];
% ASSUMPTION: the five amplitudes sum to 2.7 of full scale, which a 14-bit ADC
% cannot hold without clipping. They are scaled together so the worst-case sum
% just fits ('sum'); 'none' uses them as given and lets the ADC clip.
cfg.amplitudeNormalisation = 'sum';
cfg.noiseAfterNCI_dBFS = -75;        % [Table 3.2] "Noise level (after NCI)"
cfg.seed = 1;                        % ASSUMPTION: random start phases + noise

% --- Processing [3.2.1] ---------------------------------------------------
cfg.shiftBits = 16 - cfg.bitWidth + 16;   % "shift to 32-bit full-scale"
% FX16 quantisation [3.4.1, 4.3.3]. 'hw': keep the top 16 bits of the 32-bit
% full-scale range-FFT value, which is what his FFT IP core (16-bit in/out,
% scaled by 1/N) delivers to the compressor. 'peak': scale so a full-scale
% sinusoid maps to 32767 (the scaling used in Matlab_Sim/compress_fx16.m).
cfg.fx16Mode = 'hw';
% dBFS reference for NF and SNR. 'sinusoid': 0 dBFS = NCI power of a
% full-scale sinusoid after the whole chain (as in Matlab_Sim). 'unit':
% 0 dBFS = power 1 when the 32-bit full-scale value is 1 (no processing gain).
% Kiem does not define it; both are reported.
cfg.dbfsMode = 'sinusoid';

% --- DRHE [2.7.3, 3.5.3, Table 4.4] ----------------------------------------
cfg.alpha = 0.6;
cfg.beta  = 0.4;
% Fixed Huffman dictionary for S4, Kiem Appendix A (code lengths, S4 = 0..15)
cfg.huffLenFixed = [4 3 2 2 2 5 6 7 8 9 10 11 14 14 13 12];

% --- LPC-Huffman as described in Kiem 2.7.4 (from [25]) ------------------
cfg.lpcRawOrders = 1:10;             % ASSUMPTION: [25] order not given; swept

% --- 2nd-stage processing and detection [3.2.1, 3.4.2] --------------------
% "combination of local maxima detection with global thresholding based on
% noise estimation". ASSUMPTION for the numbers: noise estimate = mean (dB) of
% the lowest 75 % of cells; threshold = estimate + 15 dB; 8-neighbour maxima.
cfg.detNoiseFraction = 0.75;
cfg.detMargin_dB     = 15;
cfg.nfGuard          = 5;            % exclude a 5x5 patch round each detection
                                     % from the noise-floor estimate
end
