function compressedData = compress_fx16_lfr(inputData, config, params)
% COMPRESS_FX16_LFR Fixed-point (int16) quantisation with Low-Frequency Rejection.
%   Drop-in alternative to COMPRESS_FX16 that replaces the uniform fixed-scale
%   quantiser with the two-stage low-frequency-suppression companding curve of
%   Deng & Huang (2024). The goal is to cut the quantisation error of the
%   fixed-point path so it approaches the floating-point (FP16) reference.
%
%   WHY THIS REDUCES THE ERROR
%   COMPRESS_FX16 maps a worst-case full-scale sinusoid to int16 full-scale, so
%   real range-FFT data (whose peak is ~1% of that worst case) only exercises a
%   tiny fraction of the int16 codes and is quantised with a huge uniform step.
%   LFR instead (1) scales the actual data peak to int16 full-scale and (2)
%   applies a companding curve that gives fine steps to the densely populated
%   small magnitudes and coarse steps to the rare large magnitudes, matching the
%   concentrated (Rayleigh) magnitude distribution of radar data.
%
%   The complex sample is stored in POLAR form: the MAGNITUDE is companded and
%   the PHASE is preserved, then re-expressed on the int16 real/imag grid so the
%   downstream DRHE coder (COMPRESS_DRHE) consumes it unchanged. Because the
%   companded magnitude g(|z|) <= L, the stored real/imag never exceed int16
%   full-scale (no clipping).
%
%   Input:
%     inputData - complex double [numRangeBins x numRamps x numRxChannels]
%     config    - pipeline config struct (unused fields tolerated)
%     params    - (optional) LFR params from LFR_OPTIMIZE_PARAMS. If omitted,
%                 they are optimised from this frame's magnitude distribution.
%
%   Output:
%     compressedData - struct with:
%        .real_part, .imag_part  int16 companded Cartesian codes (DRHE input)
%        .scaleFactor            1 (codes ARE the companded values; kept so the
%                                DRHE path round-trips the codes losslessly)
%        .lfrParams              params needed by DECOMPRESS_FX16_LFR
%        .format                 'fx16_lfr'
%
%   See also DECOMPRESS_FX16_LFR, LFR_OPTIMIZE_PARAMS, COMPRESS_FX16, COMPRESS_DRHE.

    L = 32767;                      % int16 positive full-scale

    mag   = abs(inputData);
    phase = angle(inputData);

    if nargin < 3 || isempty(params)
        params = lfr_optimize_params(mag, L);
    end

    % --- normalise magnitude into [0, L] and compand -----------------------
    xin  = mag / params.Amax * L;
    xin  = min(xin, L);
    xout = lfr_g(xin, params);                  % companded magnitude in [0, L]

    % --- re-express on the Cartesian int16 grid (phase preserved) ----------
    reC = xout .* cos(phase);
    imC = xout .* sin(phase);

    compressedData.real_part   = int16(round(reC));
    compressedData.imag_part   = int16(round(imC));
    compressedData.scaleFactor = 1;             % codes already in companded units
    compressedData.lfrParams   = params;
    compressedData.format      = 'fx16_lfr';
end
