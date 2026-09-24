function [rd, D] = kr_second_stage(X, cfg)
%KR_SECOND_STAGE  Kiem's 2nd-stage processing [3.2.1], done in double.
%   1. Doppler FFT over the ramps with a Hanning window, divided by numRamps
%   2. non-coherent integration (NCI): sum of |.|^2 over the RX channels
%   rd is the range-Doppler power map [N/2 x numRamps].
M  = cfg.numRamps;
w  = kr_hanning(M).';
D  = fft(X .* w, M, 2) / M;
rd = sum(abs(D).^2, 3);
end
