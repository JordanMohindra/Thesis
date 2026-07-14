function x = lfr_ginv(y, params)
% LFR_GINV Inverse of the two-stage LFR companding transform (Eq. 9).
%   Reverses lfr_g so the decompressor can restore the original magnitude.
%
%   g^-1(y) = t * y / g(t)                                ,  y <  g(t)
%           = k * (exp(y * log(L/k + 1) / L) - 1)         ,  y >= g(t)
%
%   (The paper writes the log/exp in base 10; the ratio log(.)/log(.) is
%   base-independent, so natural log/exp are used here consistently with
%   lfr_g.)
%
%   Input:
%     y      - companded array in [0, L]
%     params - struct with fields .t, .k, .L (and optionally .gt)
%
%   Output:
%     x      - restored magnitude in [0, L]
%
%   See also LFR_G, LFR_INFLECTION.

    t = params.t;
    k = params.k;
    L = params.L;

    if isfield(params, 'gt')
        gt = params.gt;
    else
        gt = lfr_inflection(t, k, L);
    end

    y = max(min(y, L), 0);

    x = zeros(size(y));
    lin = y < gt;

    % Inverse linear stretch
    if gt > 0
        x(lin) = t .* y(lin) ./ gt;
    end

    % Inverse logarithmic compression
    nl = ~lin;
    x(nl) = k .* (exp(y(nl) .* log(L ./ k + 1) ./ L) - 1);

    x = max(min(x, L), 0);
end
