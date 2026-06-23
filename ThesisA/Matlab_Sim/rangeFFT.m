function rangeFFTOut = rangeFFT(preprocessedData, config)
% RANGEFFT Computes Range FFT with postprocessing.
%   As described in Section 3.2.1 of Kiem's thesis:
%   1. FFT along the samples dimension (dim 1)
%   2. Scale output by 1/numSamples (energy normalization)
%   3. Take symmetric first half (real-valued input produces symmetric FFT)
%
%   Input:
%     preprocessedData - double matrix [numSamples x numRamps x numRxChannels]
%     config           - struct with .numSamples
%
%   Output:
%     rangeFFTOut - complex double [numSamples/2 x numRamps x numRxChannels]

    nSamp = config.numSamples;
    nHalf = nSamp / 2;

    fftData = fft(preprocessedData, nSamp, 1);

    fftData = fftData / nSamp;

    rangeFFTOut = fftData(1:nHalf, :, :);
end
