function gt = lfr_inflection(t, k, L)
% LFR_INFLECTION Inflection value g(t) of the LFR companding curve (Eq. 8).
%   gt = L * log(t/k + 1) / log(L/k + 1)
%   This is the value of the companded output at the threshold t, ensuring the
%   linear-stretch and log-compression pieces of lfr_g join continuously.
%
%   See also LFR_G, LFR_GINV.

    gt = L .* log(t ./ k + 1) ./ log(L ./ k + 1);
end
