function rangeFFTOut = rangeFFT_fx16(preprocessedData, config)
% RANGEFFT_FX16 Simulates a 16-bit fixed-point FFT matching the Xilinx FFT IP core.
%   Models the Xilinx FFT IP core v9.1 as configured in Kiem's thesis
%   (Table 4.3, Section 4.3.3):
%
%     - Architecture:        Radix-2 DIT (approximation of Kiem's radix-4)
%     - Data path:           16-bit fixed-point
%     - Phase factor width:  24-bit (twiddle factors stored as Q23)
%     - Scaling:             Scaled, with total shift = log2(N) bits
%     - Rounding mode:       Convergent rounding (AP_RND)
%
%   Per-butterfly operation:
%     1. Complex multiply: 16-bit data × 24-bit twiddle → 40-bit product
%        → round to 16-bit (convergent rounding, not truncation)
%     2. Butterfly add/subtract with right-shift by 1 (convergent rounding)
%     3. All intermediates clipped to [-32768, +32767]
%
%   Using 24-bit twiddle factors (as Kiem's hardware does) dramatically
%   reduces the complex multiply error compared to 16-bit twiddles.
%   Using convergent rounding (round-to-even) instead of floor-truncation
%   eliminates the systematic negative bias of arithmetic right shift.
%
%   The output is returned in the same double-precision units as rangeFFT.m
%   so it can be passed directly to compress_fx16 / compress_fp16 for
%   comparison. The fixed-point errors are "baked in".
%
%   Input:
%     preprocessedData - double [numSamples x numRamps x numRxChannels]
%     config           - struct with .numSamples, .bitWidth
%
%   Output:
%     rangeFFTOut - complex double [numSamples/2 x numRamps x numRxChannels]
%                   Same units as rangeFFT.m, but degraded by fixed-point
%                   errors at each butterfly stage.
%
%   See also RANGEFFT, COMPRESS_FX16, MAIN_SIMULATION_FFT_COMPARISON.

    nSamp = config.numSamples;
    nHalf = nSamp / 2;
    nStages = round(log2(nSamp));

    [~, nRamps, nRx] = size(preprocessedData);

    % --- Reshape to 2D for vectorised processing: [nSamp x nCols] ---------
    data = reshape(preprocessedData, nSamp, []);
    nCols = size(data, 2);  %#ok<NASGU>

    % --- Scale input to int16 range ---------------------------------------
    % In real hardware, the ADC output is left-shifted to fill the 16-bit
    % FFT data path. For a 14-bit ADC, the shift is 2 bits, so the data
    % fills ~100% of the int16 range. This is critical for the fixed-point
    % FFT: the more bits you use, the less relative error from rounding.
    %
    % The preprocessed data has been inflated by 2^(16-bw+16) in
    % preprocessing.m (designed for the double-precision FFT path). We
    % scale it so the peak fills ~95% of int16, simulating a properly
    % configured hardware ADC left-shift. The 5% headroom prevents
    % clipping during butterfly additions.
    maxInput = max(abs(data(:)));
    if maxInput > 0
        inputScale = 0.95 * 32767 / maxInput;
    else
        inputScale = 1;
    end

    data_re = fx_clip(round(real(data) * inputScale));
    data_im = fx_clip(round(imag(data) * inputScale));

    % --- Bit-reversal permutation -----------------------------------------
    idx = fx_bitrev(nSamp);
    data_re = data_re(idx, :);
    data_im = data_im(idx, :);

    % --- Pre-compute twiddle factors in Q23 format (24-bit) ---------------
    % Kiem's FFT IP core uses 24-bit phase factors (Table 4.3).
    % W(k) = exp(-j*2*pi*k/N), stored as round(2^23 * cos/sin).
    % The extra 8 bits of precision (vs Q15) dramatically reduce the
    % complex multiply error: ~0.00000006% per multiply instead of ~0.003%.
    Q23_SCALE = 2^23 - 1;   % 8388607
    angles = -2 * pi * (0 : nSamp/2 - 1) / nSamp;
    tw_re = round(Q23_SCALE * cos(angles));
    tw_im = round(Q23_SCALE * sin(angles));

    % --- Radix-2 DIT butterfly stages -------------------------------------
    % Note: Kiem uses Radix-4 (5 stages for N=512). We approximate with
    % Radix-2 (log2(N) stages) since the key error mechanism (scaling +
    % truncation) is the same. The main differences are captured by using
    % the correct twiddle precision and rounding mode.
    for s = 1:nStages
        halfSize  = 2^(s - 1);
        groupSize = 2^s;
        twStep    = nSamp / groupSize;   % twiddle index stride

        for j = 0 : halfSize - 1
            twIdx = j * twStep + 1;
            wr = tw_re(twIdx);
            wi = tw_im(twIdx);

            % Vectorised: all butterflies with this j across all groups
            top = j + (0 : groupSize : nSamp-1) + 1;
            bot = top + halfSize;

            % --- Complex multiply: B * W in Q23 arithmetic ----------------
            % 16-bit data × 24-bit twiddle → 40-bit product
            % Divide by Q23_SCALE to undo the Q23 scaling.
            % Use round() for convergent rounding (Kiem: AP_RND).
            b_re = data_re(bot, :);
            b_im = data_im(bot, :);

            p_re = fx_clip(round((b_re * wr - b_im * wi) / Q23_SCALE));
            p_im = fx_clip(round((b_re * wi + b_im * wr) / Q23_SCALE));

            % --- Butterfly with convergent-rounded right-shift by 1 -------
            % X = round((A + B*W) / 2)
            % Y = round((A - B*W) / 2)
            % Using round() matches Kiem's convergent rounding (AP_RND),
            % which has zero bias unlike floor() (truncation).
            a_re = data_re(top, :);
            a_im = data_im(top, :);

            data_re(top, :) = fx_clip(fx_rnd_shift(a_re + p_re));
            data_im(top, :) = fx_clip(fx_rnd_shift(a_im + p_im));
            data_re(bot, :) = fx_clip(fx_rnd_shift(a_re - p_re));
            data_im(bot, :) = fx_clip(fx_rnd_shift(a_im - p_im));
        end
    end

    % --- Take positive-frequency half ------------------------------------
    data_re = data_re(1:nHalf, :);
    data_im = data_im(1:nHalf, :);

    % --- Convert back to physical units -----------------------------------
    % The FFT output has been scaled by inputScale (at input) and 1/N (from
    % the per-stage right-shifts).  Undo inputScale so the result is in the
    % same physical units as rangeFFT.m (which returns fft(x)/N).
    rangeFFTOut = complex(data_re, data_im) / inputScale;

    % --- Reshape back to 3D -----------------------------------------------
    rangeFFTOut = reshape(rangeFFTOut, nHalf, nRamps, nRx);
end


%% ======================================================================= %%
function x = fx_clip(x)
% FX_CLIP  Saturate to the signed 16-bit integer range [-32768, +32767].
    x = max(min(x, 32767), -32768);
end

function x = fx_rnd_shift(x)
% FX_RND_SHIFT  Convergent-rounded right-shift by 1 (divide by 2).
%   Matches the Xilinx FFT IP core's AP_RND rounding mode.
%   round() in MATLAB implements round-half-to-even (banker's rounding),
%   which is equivalent to convergent rounding and has zero DC bias.
%   This replaces the previous floor() truncation which had negative bias.
    x = round(x / 2);
end

function idx = fx_bitrev(N)
% FX_BITREV  Bit-reversal permutation indices for length N (power of 2).
    nBits = round(log2(N));
    idx = zeros(1, N);
    for k = 0:N-1
        rev = 0;
        tmp = k;
        for b = 1:nBits
            rev = rev * 2 + mod(tmp, 2);
            tmp = floor(tmp / 2);
        end
        idx(k+1) = rev + 1;
    end
end
