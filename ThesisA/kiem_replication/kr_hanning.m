function w = kr_hanning(L)
%KR_HANNING  MATLAB's hanning(L) (no zero end points), written out so this
%   folder needs no toolbox. Kiem uses hanning(nSamples) [5.2.5].
k = (1:L)';
w = 0.5 * (1 - cos(2*pi*k / (L + 1)));
end
