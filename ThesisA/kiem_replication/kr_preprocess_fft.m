function X = kr_preprocess_fft(adc, cfg)
%KR_PREPROCESS_FFT  Kiem's preprocessing and range FFT [3.2.1].
%   1. shift to 32-bit full scale: left shift by 16 - bitWidth + 16
%   2. Hanning window along fast time
%   3. FFT along fast time, divided by the number of samples
%   4. keep the first (positive-frequency) half
%   X is complex double in 32-bit full-scale units, [N/2 x numRamps x numRx].
N  = cfg.numSamples;
xs = double(adc) * 2^cfg.shiftBits;
xs = xs .* kr_hanning(N);
F  = fft(xs, N, 1) / N;
X  = F(1:N/2, :, :);
end
