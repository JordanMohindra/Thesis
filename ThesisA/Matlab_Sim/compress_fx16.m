function compressedData = compress_fx16(inputData, config)
% COMPRESS_FX16 Quantizes range FFT data to 16-bit fixed-point (int16).
%   Simulates the effect of a fixed-point hardware implementation as described
%   in Section 3.2 of Kiem's thesis. Uses a FIXED scale factor based on the
%   maximum possible range FFT output (full-scale sinusoid), simulating how
%   hardware pre-determines the quantization range at design time.
%
%   In a real FPGA/SoC implementation:
%   - The bit width is fixed at design time based on worst-case input
%   - Intermediate FFT stages use truncation/rounding at each butterfly
%   - The effective precision is less than the nominal 16 bits due to
%     accumulated truncation, DNL/INL, and noise coupling
%
%   To model these accumulated hardware effects, an optional effective ENOB
%   (effective number of bits) parameter can reduce precision below 16.
%
%   CR = 1 (same data size as FP16, different representation).
%
%   Input:
%     inputData - complex double [numRangeBins x numRamps x numRxChannels]
%     config    - struct with .numSamples, .bitWidth
%
%   Output:
%     compressedData - struct with quantized int16 data and scale factor

    realPart = real(inputData);
    imagPart = imag(inputData);

    % Fixed scale factor: based on maximum POSSIBLE range FFT output
    % This is what hardware would use (predetermined at design time)
    N = config.numSamples;
    shift = 16 - config.bitWidth + 16;
    maxADCVal = 2^(config.bitWidth - 1) - 1;
    hannWin = hann(N);
    maxPossibleFFT = maxADCVal * 2^shift * sum(hannWin) / (2 * N);

    int16Max = 32767;
    scaleFactor = int16Max / maxPossibleFFT;

    % Quantize to int16
    realQuantized = int16(round(realPart * scaleFactor));
    imagQuantized = int16(round(imagPart * scaleFactor));

    % --- Effective number of bits (ENOB) reduction ---
    % A real fixed-point FFT pipeline does NOT achieve the full 16-bit
    % resolution: every butterfly stage truncates/rounds, DNL/INL and noise
    % coupling eat into the LSBs, so the effective resolution is < 16 bits.
    % We model this by discarding the lowest (16 - ENOB) bits of the int16
    % code. This is the dominant reason hardware FX16 loses to FP16: the
    % floating-point exponent preserves low-level detail that the truncated
    % fixed-point LSBs throw away. With ENOB = 16 this is a no-op.
    if isfield(config, 'fx16EffectiveBits')
        enob = config.fx16EffectiveBits;
    else
        enob = 16;
    end
    if enob < 16
        quantStep = 2^(16 - enob);
        realQuantized = int16(round(double(realQuantized) / quantStep) * quantStep);
        imagQuantized = int16(round(double(imagQuantized) / quantStep) * quantStep);
    end

    compressedData.real_part = realQuantized;
    compressedData.imag_part = imagQuantized;
    compressedData.scaleFactor = scaleFactor;
    compressedData.effectiveBits = enob;
    compressedData.format = 'fx16';
end
