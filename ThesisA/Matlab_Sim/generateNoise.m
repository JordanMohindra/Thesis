function noise = generateNoise(noiseType, nSamp, nRamp, sigma, params)
% GENERATENOISE Builds a 2-D noise matrix [nSamp x nRamp] for one RX channel.
%
%   noise = generateNoise(type, nSamp, nRamp, sigma, params)
%
%   ALL noise types return a matrix with per-sample STD ~ sigma (variance
%   preserving). This keeps the broadband noise-floor MEASUREMENT (NF, in
%   dBFS) roughly the same across types so DRHE's compression behaviour can
%   be compared apples-to-apples.
%
%   noiseType : 'white'         AWGN (default; what every textbook assumes).
%               'ar1_slow'      AR(1) correlation along the slow-time (ramp)
%                               axis. params.rho in [0,1) controls correlation.
%                               High rho -> ramps look alike -> DRHE residuals
%                               small (high CR) BUT energy concentrates at low
%                               Doppler (broadband NF measurement drops).
%               'ar1_fast'      AR(1) along fast-time (sample) axis. Colours
%                               the range FFT (energy concentrates at low
%                               range bins) but is uncorrelated ramp-to-ramp,
%                               so it does NOT help DRHE.
%               'colored_slow'  Low-pass FIR-shaped slow-time noise.
%                               params.bw in (0,0.5] is the one-sided cutoff
%                               as a fraction of the ramp rate. Smaller bw
%                               -> more correlated in slow time, similar
%                               trade-off to ar1_slow but with finer control.
%               'pink_slow'     1/f spectrum along slow-time (oscillator-like
%                               phase noise). Long-range correlations -> good
%                               for DRHE, but energy heavily skewed to low
%                               Doppler.
%               'mixed'         alpha * slow-time-correlated + (1-alpha) * white.
%                               params.rho is the AR(1) coefficient and
%                               params.alpha in [0,1] is the fraction of
%                               TOTAL VARIANCE that is correlated. This is
%                               the closest model to real radar noise: a
%                               compressible component (oscillator/clutter
%                               tails) on top of an incompressible thermal
%                               component (true Johnson noise).
%
%   The output noise has zero mean and std = sigma per sample (within a few %
%   for the deterministic-spectrum models).

    if nargin < 5
        params = struct();
    end

    switch lower(noiseType)
        case 'white'
            noise = sigma * randn(nSamp, nRamp);

        case 'ar1_slow'
            rho = getp(params, 'rho', 0.9);
            innov = randn(nSamp, nRamp);
            n = zeros(nSamp, nRamp);
            n(:, 1) = innov(:, 1);
            s = sqrt(1 - rho^2);
            for mm = 2:nRamp
                n(:, mm) = rho * n(:, mm-1) + s * innov(:, mm);
            end
            % AR(1) with innovation std = sqrt(1-rho^2) gives stationary std = 1
            noise = sigma * n;

        case 'ar1_fast'
            rho = getp(params, 'rho', 0.9);
            innov = randn(nSamp, nRamp);
            n = zeros(nSamp, nRamp);
            n(1, :) = innov(1, :);
            s = sqrt(1 - rho^2);
            for kk = 2:nSamp
                n(kk, :) = rho * n(kk-1, :) + s * innov(kk, :);
            end
            noise = sigma * n;

        case 'colored_slow'
            bw = getp(params, 'bw', 0.1);
            bw = max(min(bw, 0.49), 1e-3);
            % Design a short low-pass FIR with cutoff = bw (normalised to
            % Nyquist of the ramp axis). Apply to white slow-time noise.
            ntaps = 31;
            taps = fir1(ntaps - 1, 2 * bw);
            w = randn(nSamp, nRamp);
            % Apply filter along the slow-time (column) axis for each row
            n = filter(taps, 1, w, [], 2);
            % Renormalise to unit per-sample variance
            n = n / std(n(:));
            noise = sigma * n;

        case 'pink_slow'
            % Per row, generate 1/f noise along the ramp axis via FFT-shaping.
            n = zeros(nSamp, nRamp);
            f = (0:nRamp-1);
            f(1) = 1;  % avoid divide-by-zero at DC
            shape = 1 ./ sqrt(f);
            shape(nRamp/2 + 2 : end) = shape(nRamp/2:-1:2);   % conjugate-symmetric
            for kk = 1:nSamp
                w = randn(1, nRamp) + 1j * randn(1, nRamp);
                n(kk, :) = real(ifft(w .* shape));
            end
            n = n / std(n(:));
            noise = sigma * n;

        case 'mixed'
            rho   = getp(params, 'rho', 0.95);
            alpha = getp(params, 'alpha', 0.5);
            alpha = max(min(alpha, 1), 0);
            % Correlated component (AR(1) slow-time, unit variance)
            innov = randn(nSamp, nRamp);
            nc = zeros(nSamp, nRamp);
            nc(:, 1) = innov(:, 1);
            s = sqrt(1 - rho^2);
            for mm = 2:nRamp
                nc(:, mm) = rho * nc(:, mm-1) + s * innov(:, mm);
            end
            % White component (unit variance)
            nw = randn(nSamp, nRamp);
            % Variance-preserving blend: total variance = alpha + (1-alpha) = 1
            n  = sqrt(alpha) * nc + sqrt(1 - alpha) * nw;
            noise = sigma * n;

        otherwise
            error('generateNoise:unknownType', ...
                  'Unknown noise type "%s".', noiseType);
    end
end

function v = getp(s, name, default)
    if isfield(s, name)
        v = s.(name);
    else
        v = default;
    end
end
