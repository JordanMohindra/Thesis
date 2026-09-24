function [dre, dim] = kr_drhe_encode(re, im, cfg, lag)
%KR_DRHE_ENCODE  Kiem's DRHE model prediction and difference [3.5.3].
%   re, im : FX16 integers [bins x ramps x rx]
%   dre,dim: X - X_hat, wrapped to int16, same size
%   The model is initialised with zero at the first ramp [3.5.4] and updated
%   from the input sample (open loop, as in Kiem's Figure 3.16 and HLS code).
%   lag (default 1) predicts ramp m from ramp m - lag. Kiem's radar has one
%   transmitter, so lag = 1; lag = nTx is the TDM correction of this thesis.
if nargin < 4, lag = 1; end
[B, M, R] = size(re);
dre = zeros(B, M, R); dim = zeros(B, M, R);
for p = 1:lag                         % independent predictor per TX slot
    st = zeroState(B, R);
    for m = p:lag:M
        [pre, pim, st] = kr_drhe_predict_step(st, cfg.alpha, cfg.beta);
        x = squeeze3(re(:, m, :)); y = squeeze3(im(:, m, :));
        dre(:, m, :) = reshape(kr_wrap16(x - pre), B, 1, R);
        dim(:, m, :) = reshape(kr_wrap16(y - pim), B, 1, R);
        st = kr_drhe_update(st, x, y);
    end
end
end

function st = zeroState(B, R)
z = zeros(B, R);
st = struct('magPred', z, 'mag', z, 'phPred', z, 'ph', z, 'ph2', z);
end

function a = squeeze3(a)
a = reshape(a, size(a, 1), size(a, 3));
end
