function params = lfr_optimize_params(magData, L, opts)
% LFR_OPTIMIZE_PARAMS Select LFR companding parameters (t, k) for a dataset.
%   Implements the parameter-selection stage of the low-frequency suppression
%   algorithm (Deng & Huang 2024, Section 3.1.4): first fit the data
%   distribution, then choose (t, k) that minimise the quantisation loss.
%
%   The paper assumes a Rayleigh magnitude distribution described by a single
%   parameter sigma, and minimises the analytic loss of Eq. (20). Here we (a)
%   report the fitted Rayleigh sigma for reference, and (b) select (t, k) by
%   directly minimising the EMPIRICAL quantisation MSE on the actual data,
%   which is the paper's "refined selection" mode and is robust to deviations
%   from the ideal Rayleigh model. A coarse grid search ("rough mode") is
%   followed by a local refinement around the best point.
%
%   Input:
%     magData - array of non-negative magnitudes (any shape)
%     L       - companding range upper bound (e.g. 32767 for int16)
%     opts    - (optional) struct:
%                 .nSample   max samples used for the search (default 60000)
%                 .nT        threshold grid points     (default 24)
%                 .nK        compression grid points   (default 24)
%
%   Output:
%     params  - struct with fields:
%                 .t, .k, .L, .gt   companding parameters
%                 .Amax             magnitude that maps to L (data peak)
%                 .sigma            fitted Rayleigh sigma (data units)
%                 .mseNorm          normalised MSE achieved (in [0,L] domain)
%                 .l, .p            avg derivatives below/above t (Eq. 19)
%
%   See also LFR_G, LFR_GINV, COMPRESS_FX16_LFR.

    if nargin < 3 || isempty(opts); opts = struct(); end
    if ~isfield(opts, 'nSample'); opts.nSample = 60000; end
    if ~isfield(opts, 'nT');      opts.nT      = 24;    end
    if ~isfield(opts, 'nK');      opts.nK      = 24;    end

    mag = double(magData(:));
    Amax = max(mag);
    if Amax <= 0; Amax = 1; end

    % --- Rayleigh fit (sigma_hat = sqrt(mean(x^2)/2)), reported for reference
    sigma = sqrt(mean(mag.^2) / 2);

    % --- normalise magnitudes into the companding domain [0, L]
    xin = mag / Amax * L;

    % --- subsample for the search (speed)
    if numel(xin) > opts.nSample
        idx = round(linspace(1, numel(xin), opts.nSample));
        xs = xin(idx);
    else
        xs = xin;
    end

    % --- grid: t spans the populated low range; k spans several decades.
    tGrid = L * logspace(log10(1e-3), log10(1), opts.nT);   % 0.1%..100% of L
    kGrid = L * logspace(-6, 1, opts.nK);                   % wide compression range

    [bestT, bestK, bestMse] = gridSearch(xs, L, tGrid, kGrid);

    % --- local refinement around the best grid point ("refined mode")
    tLo = bestT / 3;  tHi = min(bestT * 3, L);
    kLo = bestK / 5;  kHi = bestK * 5;
    tGrid2 = linspace(tLo, tHi, opts.nT);
    kGrid2 = logspace(log10(kLo), log10(kHi), opts.nK);
    [bestT, bestK, bestMse] = gridSearch(xs, L, tGrid2, kGrid2, bestT, bestK, bestMse);

    gt = lfr_inflection(bestT, bestK, L);

    params = struct();
    params.t       = bestT;
    params.k       = bestK;
    params.L       = L;
    params.gt      = gt;
    params.Amax    = Amax;
    params.sigma   = sigma;
    params.mseNorm = bestMse;
    params.l       = gt / bestT;                 % avg derivative below t (Eq. 19)
    params.p       = (L - gt) / (L - bestT);     % avg derivative above t (Eq. 19)
end

%% ----------------------------------------------------------------------- %%
function [bestT, bestK, bestMse] = gridSearch(xs, L, tGrid, kGrid, bestT, bestK, bestMse)
    if nargin < 7
        bestT = tGrid(1); bestK = kGrid(1); bestMse = inf;
    end
    for it = 1:numel(tGrid)
        t = tGrid(it);
        for ik = 1:numel(kGrid)
            k = kGrid(ik);
            p = struct('t', t, 'k', k, 'L', L, 'gt', lfr_inflection(t, k, L));
            yq = round(lfr_g(xs, p));            % compand + quantise
            xr = lfr_ginv(yq, p);                % restore
            mse = mean((xr - xs).^2);
            if mse < bestMse
                bestMse = mse; bestT = t; bestK = k;
            end
        end
    end
end
