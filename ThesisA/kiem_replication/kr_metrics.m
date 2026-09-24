function m = kr_metrics(detRef, detTest, rdTest, cfg, CR)
%KR_METRICS  Kiem's evaluation metrics [2.2.3, 3.4.2].
%   CR     compression ratio (passed in)
%   FN_pct targets in the reference list missed by the test list, as a
%          percentage of the reference detections
%   FP_pct detections in the test list that are not in the reference list,
%          as a percentage of the reference detections (Kiem's 0.59 % and
%          1.18 % are 1 and 2 of his 169 reference detections)
%   NF     mean, in dBFS, of the range-Doppler cells away from detections
%          ("the mean of the noisy part of the signal in dB")
%   SNR    signal RMS in dB (at the detected peaks) minus NF
%   NF and SNR are given for both dBFS references (see kr_fullscale_ref).
m.CR = CR;
nRef = nnz(detRef);
m.nRef  = nRef;
m.nTest = nnz(detTest);
m.FN_pct  = 100 * nnz(detRef & ~detTest) / max(nRef, 1);
m.FP_pct  = 100 * nnz(detTest & ~detRef) / max(nRef, 1);
m.FDR_pct = 100 * nnz(detTest & ~detRef) / max(m.nTest, 1);
m.zeroCellPct = 100 * mean(rdTest(:) <= kr_fullscale_ref(cfg) * 1e-20);
g = cfg.nfGuard;
near = conv2(double(detTest), ones(g), 'same') > 0;
cfgS = cfg; cfgS.dbfsMode = 'sinusoid';
cfgU = cfg; cfgU.dbfsMode = 'unit';
for pass = 1:2
    if pass == 1, P = kr_fullscale_ref(cfgS); else, P = kr_fullscale_ref(cfgU); end
    L  = 10*log10(max(rdTest / P, 1e-20));      % same -200 dBFS floor as kr_detect
    keep = ~near & rdTest / P > 1e-20;          % cells coded to exactly zero
    if ~any(keep(:)), keep = ~near; end         % carry no noise information
    nf = mean(L(keep));
    if any(detTest(:)), sig = 10*log10(mean(rdTest(detTest)) / P); else, sig = nf; end
    if pass == 1, m.NF = nf; m.SNR = sig - nf; else, m.NF_unit = nf; m.SNR_unit = sig - nf; end
end
end
