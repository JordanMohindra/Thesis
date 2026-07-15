function P_ref = computeFullScaleRefPower(config)
% COMPUTEFULLSCALEREFPOWER Computes the 0 dBFS reference power.
%   This is the power a full-scale sinusoid (amplitude = maxADCVal) would
%   produce after the full processing chain:
%     Preprocessing -> Range FFT -> Doppler FFT -> NCI
%
%   For a real cosine at exact bin centers:
%     After Range FFT (Hanning, /N):  peak = A_preproc * sum(hann_R) / (2*N)
%     After Doppler FFT (Hanning, /M): peak *= sum(hann_D) / M
%     After NCI (nRx channels):        power = nRx * |peak|^2
%
%   Input:
%     config - struct with .numSamples, .numRamps, .numRxChannels, .bitWidth
%
%   Output:
%     P_ref - full-scale reference power (0 dBFS level)

    N = config.numSamples;
    M = config.numRamps;
    nRx = config.numRxChannels;
    shift = 16 - config.bitWidth + 16;
    maxADCVal = 2^(config.bitWidth - 1) - 1;

    % Full-scale amplitude after preprocessing
    A_preproc = maxADCVal * 2^shift;

    % Range FFT peak for a real cosine (Hanning window, /N normalization)
    % Peak at positive freq bin = A_preproc * sum(hann(N)) / (2*N)
    hannR = hann(N);
    peakAfterRangeFFT = A_preproc * sum(hannR) / (2 * N);

    % Doppler FFT peak for complex exponential (Hanning window, /M normalization)
    % Input is complex exp across ramps -> peak = amplitude * sum(hann(M)) / M
    hannD = hann(M);
    peakAfterDopplerFFT = peakAfterRangeFFT * sum(hannD) / M;

    % NCI: sum of |peak|^2 across nRx channels
    P_ref = nRx * abs(peakAfterDopplerFFT)^2;
end
