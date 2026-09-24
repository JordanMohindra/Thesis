function nf = kr_find_nf_for_cr(cfg, targetCR, field)
%KR_FIND_NF_FOR_CR  Noise floor (dBFS after NCI) at which the given method
%   reaches the target compression ratio on this scene, by bisection.
%   CR falls monotonically as the noise floor rises.
lo = -120; hi = -60;
for it = 1:12
    mid = (lo + hi) / 2;
    r = kr_run_scene(cfg, struct('lite', true, 'noiseNF', mid, 'skipRaw', true));
    if r.metrics.(field).CR > targetCR, lo = mid; else, hi = mid; end
end
nf = (lo + hi) / 2;
end
