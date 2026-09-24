function [sigma, nf1] = kr_calibrate_noise(cfg, targetNF_dBFS)
%KR_CALIBRATE_NOISE  ADC noise standard deviation (in ADC codes) that gives
%   the requested noise floor after the full chain, measured exactly as the
%   NF metric measures it (mean in dB over the range-Doppler cells).
%   The chain is linear, so one noise-only run at sigma = 1 fixes the scale:
%   NF(sigma) = NF(1) + 20 log10(sigma).
if nargin < 2, targetNF_dBFS = cfg.noiseAfterNCI_dBFS; end
rng(cfg.seed + 1000);
w = randn(cfg.numSamples, cfg.numRamps, cfg.numRx);
xs = w * 2^cfg.shiftBits .* kr_hanning(cfg.numSamples);
F  = fft(xs, cfg.numSamples, 1) / cfg.numSamples;
X  = F(1:cfg.numSamples/2, :, :);
rd = kr_second_stage(X, cfg);
nf1 = mean(10*log10(rd(:) / kr_fullscale_ref(cfg)));
sigma = 10^((targetNF_dBFS - nf1) / 20);
end
