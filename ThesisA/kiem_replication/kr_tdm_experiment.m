%% KR_TDM_EXPERIMENT
%  Why the ColoRadar results of this thesis differ from Kiem's: the same
%  chain as run_kiem_replication.m, run on
%    (a) Kiem's radar: one transmitter, every ramp from the same antenna, and
%    (b) the ramps interleaved over 12 transmitters, as in the ColoRadar
%        cascade (ramp m sent by TX mod(m,12), each at its own place in the
%        virtual array),
%  each coded with prediction from the previous ramp (lag 1, DRHE and LPC as
%  published) and from the previous ramp of the same transmitter (lag 12, the
%  correction in this thesis).
%
%  Two scenes. 'kiem' is Kiem's Table 3.2 scene: five targets in 512 range
%  bins, so almost every cell is noise and prediction has little to work on.
%  'dense' is NOT from Kiem: 300 scatterers spread over range with small
%  Doppler and random angles, amplitudes between -70 and -30 dB of full scale,
%  a stand-in for a real street scene (Kiem's real data gave 169 detections).
%  Output: results/tdm_experiment.txt

clear; close all;
here = fileparts(mfilename('fullpath')); addpath(here);
outDir = fullfile(here, 'results'); if ~exist(outDir, 'dir'), mkdir(outDir); end
diary(fullfile(outDir, 'tdm_experiment.txt'));
cfg0 = kr_config('sim');
cfg0.numRamps = 504;                     % a whole number of 12-ramp cycles
dense = cfg0;
rng(7); K = 300;
dense.targets.rangeBin   = randi([20 500], 1, K);
dense.targets.dopplerBin = randi([-20 20], 1, K);
dense.targets.amplitude  = 10.^(-(1.5 + 2*rand(1, K)));
dense.targets.angleDeg   = -60 + 120*rand(1, K);
dense.amplitudeNormalisation = 'none';
scenes = {'kiem', cfg0; 'dense', dense};
for s = 1:2
  for nf = [-75 -95]
    fprintf('\n=== scene %s, noise floor %d dBFS ===\n', scenes{s,1}, nf);
    fprintf('%-20s %9s %9s %9s %9s\n', 'radar / lag', 'DRHE', 'DRHE+RLE', 'LPC', 'NoPred');
    for tdm = [1 12]
        cfg = scenes{s,2}; cfg.tdmTx = tdm;
        for lag = unique([1 tdm])
            r = kr_run_scene(cfg, struct('lite', true, 'noiseNF', nf, 'lag', lag, 'skipRaw', true));
            m = r.metrics;
            fprintf('%2d TX, lag %2d        %9.3f %9.3f %9.3f %9.3f\n', tdm, lag, ...
                m.DRHE_fixed.CR, m.DRHE_RLE.CR, m.LPC_FFT.CR, m.NoPred.CR);
            assert(r.drheLossless && r.lpcFFTLossless);
        end
    end
  end
end
diary off;
