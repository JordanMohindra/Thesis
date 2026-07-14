function y = lfr_g(x, params)
% LFR_G Two-stage low-frequency-suppression (companding) transform g(x).
%   Implements Eq. (7)-(8) of Deng & Huang (2024), "SAR Image Compression
%   Based on Low-Frequency Rejection and Quality Map Guidance".
%
%   The transform operates on a non-negative magnitude variable x in [0, L]
%   and maps it back to [0, L] using two pieces:
%       * x < t : LINEAR STRETCH of the densely populated small/high-frequency
%                 values (slope l = g(t)/t > 1), giving them more quantization
%                 levels.
%       * x >= t: LOGARITHMIC COMPRESSION of the sparse large/low-frequency
%                 values, freeing up levels for the stretched region.
%   The net effect is a companding curve whose quantization step is fine where
%   the data are dense and coarse where the data are sparse, minimising the
%   total quantisation MSE for a concentrated (Rayleigh-like) distribution.
%
%   g(x) = g(t) * x / t                              ,  x <  t
%        = L * log(x/k + 1) / log(L/k + 1)           ,  x >= t
%   with the continuity inflection point
%   g(t) = L * log(t/k + 1) / log(L/k + 1).
%
%   Input:
%     x      - non-negative array in [0, L]
%     params - struct with fields .t, .k, .L (and optionally .gt)
%
%   Output:
%     y      - companded values in [0, L]
%
%   See also LFR_GINV, LFR_OPTIMIZE_PARAMS, COMPRESS_FX16_LFR.

    t = params.t;
    k = params.k;
    L = params.L;

    if isfield(params, 'gt')
        gt = params.gt;
    else
        gt = lfr_inflection(t, k, L);
    end

    x = max(min(x, L), 0);

    y = zeros(size(x));
    lin = x < t;

    % Linear stretch (high-frequency / small values)
    if t > 0
        y(lin) = gt .* x(lin) ./ t;
    end

    % Logarithmic compression (low-frequency / large values)
    nl = ~lin;
    y(nl) = L .* log(x(nl) ./ k + 1) ./ log(L ./ k + 1);
end
