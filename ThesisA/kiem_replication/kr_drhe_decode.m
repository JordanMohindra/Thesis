function [re, im] = kr_drhe_decode(dre, dim, cfg, lag)
%KR_DRHE_DECODE  Inverse model prediction [3.5.4, Figure 3.19]: add the
%   decoded difference to the same prediction, then update the model with the
%   restored sample. Used to prove the round trip is lossless.
if nargin < 4, lag = 1; end
[B, M, R] = size(dre);
re = zeros(B, M, R); im = zeros(B, M, R);
for p = 1:lag
    z = zeros(B, R);
    st = struct('magPred', z, 'mag', z, 'phPred', z, 'ph', z, 'ph2', z);
    for m = p:lag:M
        [pre, pim, st] = kr_drhe_predict_step(st, cfg.alpha, cfg.beta);
        x = kr_wrap16(reshape(dre(:, m, :), B, R) + pre);
        y = kr_wrap16(reshape(dim(:, m, :), B, R) + pim);
        re(:, m, :) = reshape(x, B, 1, R);
        im(:, m, :) = reshape(y, B, 1, R);
        st = kr_drhe_update(st, x, y);
    end
end
end
