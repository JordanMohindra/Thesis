function det = kr_detect(rd, cfg)
%KR_DETECT  Peak detection [3.2.1]: "a combination of local maxima detection
%   with global thresholding based on noise estimation".
%   Noise estimate: mean (dB) of the lowest cfg.detNoiseFraction of all cells.
%   Threshold: estimate + cfg.detMargin_dB. A detection is a cell above the
%   threshold that is strictly larger than its 8 neighbours (edges excluded).
% a floor 200 dB below full scale keeps cells that lossy coding set exactly
% to zero from dominating the noise estimate with -3000 dB values
floorP = kr_fullscale_ref(cfg) * 1e-20;
L  = 10*log10(max(rd, floorP));
% the noise estimate ignores cells with no energy at all (only lossy coding
% produces them); otherwise they drag the estimate, and the threshold, to the
% floor and every noise ripple becomes a detection
s  = sort(L(rd > floorP));
if isempty(s), s = L(:); end
nf = mean(s(1:max(1, round(cfg.detNoiseFraction * numel(s)))));
above = L > nf + cfg.detMargin_dB;
[nr, nc] = size(L);
c  = L(2:nr-1, 2:nc-1);
lm = true(size(c));
for dr = -1:1
    for dc = -1:1
        if dr == 0 && dc == 0, continue; end
        lm = lm & c > L((2:nr-1) + dr, (2:nc-1) + dc);
    end
end
det = false(nr, nc);
det(2:nr-1, 2:nc-1) = lm;
det = det & above;
end
