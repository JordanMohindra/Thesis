function outputData = decompress_fx16_lfr(compressedData)
% DECOMPRESS_FX16_LFR Inverse of COMPRESS_FX16_LFR.
%   Recovers the complex range-FFT data from the companded int16 codes by
%   inverting the low-frequency-suppression curve on the magnitude and
%   restoring the preserved phase.
%
%   Steps:
%     1. read companded Cartesian codes (real/imag int16, divided by scaleFactor
%        which is 1 here; this also accepts codes round-tripped by DECOMPRESS_DRHE)
%     2. companded magnitude  xout = sqrt(reC^2 + imC^2),  phase = atan2(imC, reC)
%     3. restore normalised magnitude  xin = g^-1(xout)
%     4. de-normalise  mag = xin / L * Amax  and rebuild  z = mag * exp(j*phase)
%
%   Input:
%     compressedData - struct from COMPRESS_FX16_LFR (with .lfrParams) OR a
%                      struct carrying DRHE-reconstructed codes plus .lfrParams.
%
%   Output:
%     outputData - complex double [numRangeBins x numRamps x numRxChannels]
%
%   See also COMPRESS_FX16_LFR, LFR_GINV, DECOMPRESS_DRHE.

    params = compressedData.lfrParams;
    L      = params.L;

    sf = 1;
    if isfield(compressedData, 'scaleFactor') && ~isempty(compressedData.scaleFactor)
        sf = compressedData.scaleFactor;
    end

    reC = double(compressedData.real_part) / sf;
    imC = double(compressedData.imag_part) / sf;

    xout  = sqrt(reC.^2 + imC.^2);
    phase = atan2(imC, reC);

    xin = lfr_ginv(xout, params);
    mag = xin / L * params.Amax;

    outputData = mag .* exp(1j * phase);
end
