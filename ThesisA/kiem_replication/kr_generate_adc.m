function [adc, info] = kr_generate_adc(cfg, sigmaLSB)
%KR_GENERATE_ADC  Raw ADC cube for Kiem's simulated FMCW scene [3.2.2].
%
%   adc = kr_generate_adc(cfg, sigmaLSB) returns an int16 array
%   [numSamples x numRamps x numRx] of signed ADC codes with cfg.bitWidth
%   bits. The beat signal of each target is a real cosine: its frequency sets
%   the range bin, its phase advance from ramp to ramp sets the Doppler bin,
%   and its phase across the receivers sets the angle. Additive white
%   Gaussian noise of standard deviation sigmaLSB (in ADC codes) is added
%   before the ADC rounds and clips. sigmaLSB comes from kr_calibrate_noise.
%
%   With cfg.tdmTx > 1 the ramps are transmitted by tdmTx transmitters in turn
%   (ramp m by TX mod(m, tdmTx)), each at its own position in a virtual array,
%   as in a TDM-MIMO cascade. Kiem's radar is cfg.tdmTx = 1.

N = cfg.numSamples; M = cfg.numRamps; R = cfg.numRx;
fs = 2^(cfg.bitWidth - 1) - 1;                  % largest positive ADC code
t  = cfg.targets;
K  = numel(t.rangeBin);

switch cfg.amplitudeNormalisation
    case 'sum',  ampScale = min(1, 0.999 / sum(t.amplitude));
    case 'none', ampScale = 1;
    otherwise, error('unknown amplitudeNormalisation');
end

rng(cfg.seed);
phi0 = 2*pi*rand(1, K);                          % random start phase per target

n  = (0:N-1)';
m  = 0:M-1;
tx = mod(m, cfg.tdmTx);                          % transmitter of each ramp
A  = t.amplitude(:) * ampScale * fs;             % [K x 1]
wr = 2*pi * n * t.rangeBin(:).' / N;             % fast-time phase  [N x K]
wd = 2*pi * t.dopplerBin(:) * m / M;             % slow-time phase  [K x M]
sa = sind(t.angleDeg(:));                        % [K x 1]
x  = zeros(N, M, R);
for r = 1:R
    % virtual-array element of receiver r on the transmitter of each ramp,
    % half-wavelength spacing; cos(a+b) = cos a cos b - sin a sin b, so the
    % sum over targets is two matrix products
    elem = (r - 1) + R * tx;                     % [1 x M]
    psi  = wd + pi * sa * elem + phi0(:);        % [K x M]
    x(:, :, r) = cos(wr) * (A .* cos(psi)) - sin(wr) * (A .* sin(psi));
end

x = x + sigmaLSB * randn(N, M, R);

lo = -2^(cfg.bitWidth - 1); hi = 2^(cfg.bitWidth - 1) - 1;
q  = round(x);
info.clippedFraction = mean(q(:) < lo | q(:) > hi);
q  = min(max(q, lo), hi);
adc = int16(q);
info.ampScale = ampScale;
info.sigmaLSB = sigmaLSB;
info.phi0     = phi0;
end
