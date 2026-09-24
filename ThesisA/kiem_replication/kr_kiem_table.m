function K = kr_kiem_table()
%KR_KIEM_TABLE  Kiem's published Table 3.5 (and 3.6): CR, FN %, FP %,
%   NF est. (dBFS), SNR (dB). Obtained on his real CTRX data, not on the
%   simulated scene; given here only so the two can be read side by side.
K.FP16       = [1    0    0    -70.714 22.407];
K.FX16       = [1    0.59 1.18 -70.691 22.33];
K.CMPRA      = [2    0.59 0.59 -70.687 22.418];
K.CMPRB      = [4    7.69 4.73 -70.253 22.111];
K.EGE10      = [1.6  1.18 1.18 -70.689 22.403];
K.EGE8       = [2    2.37 2.37 -70.64  22.289];
K.EGE6       = [2.67 7.69 7.1  -70.367 22.197];
K.EGE4       = [4    40.24 26.63 -74.689 28.245];
K.DRHE       = [3.25 0.59 1.18 -70.691 22.33];
K.DRHE_noRLE = [3.24 0.59 1.18 -70.691 22.33];
end
