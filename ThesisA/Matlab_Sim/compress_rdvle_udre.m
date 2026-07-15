function compressedData = compress_rdvle_udre(fx16Data, config)
% COMPRESS_RDVLE_UDRE Combined RDVLE + UDRE compression.
%   Implements both algorithms from Liang Li's thesis (2014):
%
%   Stage 1 — RDVLE (Range Dependent Variable Length Encoding):
%     Bit-cuts each range bin based on the 1/R^4 power decay model,
%     allocating fewer bits to distant range bins. The raw R^4 curve is
%     scaled so that at most maxBitsToRemove LSBs are cut at the farthest
%     bin, preventing over-aggressive zeroing of far-range data.
%
%   Stage 2 — UDRE (Uniform Dynamic Range Encoding):
%     After RDVLE bit-cutting, applies block-based uniform re-encoding
%     (similar to block floating point). Within each block of range bins,
%     a shared exponent captures the block's dynamic range, and samples
%     are re-quantized relative to that exponent. This mitigates the
%     distortion at range-bin boundaries caused by RDVLE's step-wise
%     bit allocation and further improves the compression ratio.
%
%   Combined CR ≈ 2.2 (per thesis MATLAB simulation results).
%
%   Input:
%     fx16Data - struct from compress_fx16 with .real_part (int16),
%                .imag_part (int16), .scaleFactor
%     config   - struct with .numRamps, .numRxChannels
%
%   Output:
%     compressedData - struct with encoded data, bit profile, block
%                      exponents, .totalBits, .inputBits, .CR

    % --- RDVLE parameters ---
    maxBits         = 16;
    minBits         = 4;
    maxBitsToRemove = 3;    % max LSBs cut at the farthest range bin

    % --- UDRE parameters ---
    blockSize       = 16;    % samples per UDRE block (along range)
    udreBitsPerSamp = 6;     % bits per I/Q sample after UDRE re-encoding
    udreMaxVal      = 2^(udreBitsPerSamp - 1) - 1;  % max quantised value

    realData = double(fx16Data.real_part);
    imagData = double(fx16Data.imag_part);

    [nRangeBins, nRamps, nRx] = size(realData);

    % =====================================================================
    % Stage 1: RDVLE — Range-dependent bit-cutting (scaled R^4 curve)
    % =====================================================================
    % Raw R^4 dynamic range across all bins (in bits):
    rawDR_bits = 40 * log10(nRangeBins) / 6.02;
    if rawDR_bits > 0
        scaleFactor_profile = maxBitsToRemove / rawDR_bits;
    else
        scaleFactor_profile = 0;
    end

    bitProfile = zeros(nRangeBins, 1);
    for n = 1:nRangeBins
        if n <= 1
            bitProfile(n) = maxBits;
        else
            rawRemove = 40 * log10(n) / 6.02;
            bitsToRemove = floor(rawRemove * scaleFactor_profile);
            bitProfile(n) = max(minBits, maxBits - bitsToRemove);
        end
    end

    % Apply bit-cutting
    rdvleReal = zeros(nRangeBins, nRamps, nRx);
    rdvleImag = zeros(nRangeBins, nRamps, nRx);

    for n = 1:nRangeBins
        shift = maxBits - bitProfile(n);
        if shift > 0
            divisor = 2^shift;
            rdvleReal(n, :, :) = round(realData(n, :, :) / divisor);
            rdvleImag(n, :, :) = round(imagData(n, :, :) / divisor);
        else
            rdvleReal(n, :, :) = realData(n, :, :);
            rdvleImag(n, :, :) = imagData(n, :, :);
        end
    end

    % =====================================================================
    % Stage 2: UDRE — Uniform Dynamic Range Encoding (block floating point)
    % =====================================================================
    nBlocks = ceil(nRangeBins / blockSize);

    codesReal  = zeros(nRangeBins, nRamps, nRx);
    codesImag  = zeros(nRangeBins, nRamps, nRx);
    shiftVals  = uint8(zeros(nBlocks, nRamps, nRx));

    for rx = 1:nRx
        for m = 1:nRamps
            for b = 1:nBlocks
                idxStart = (b - 1) * blockSize + 1;
                idxEnd   = min(b * blockSize, nRangeBins);

                blockReal = rdvleReal(idxStart:idxEnd, m, rx);
                blockImag = rdvleImag(idxStart:idxEnd, m, rx);

                % Find max absolute value in the block
                maxVal = max(max(abs(blockReal)), max(abs(blockImag)));

                if maxVal == 0
                    blkShift = 0;
                else
                    % Compute shift so that maxVal / 2^shift <= udreMaxVal
                    blkShift = max(0, ceil(log2(maxVal / udreMaxVal)));
                end

                % Quantize within the block
                qReal = round(blockReal ./ (2^blkShift));
                qImag = round(blockImag ./ (2^blkShift));

                % Clip to valid range
                qReal = max(min(qReal, udreMaxVal), -udreMaxVal - 1);
                qImag = max(min(qImag, udreMaxVal), -udreMaxVal - 1);

                codesReal(idxStart:idxEnd, m, rx) = qReal;
                codesImag(idxStart:idxEnd, m, rx) = qImag;
                shiftVals(b, m, rx) = uint8(blkShift);
            end
        end
    end

    % =====================================================================
    % Compute compressed size
    % =====================================================================
    inputBits = numel(realData) * 2 * 16;

    % Data bits: udreBitsPerSamp bits per I, udreBitsPerSamp bits per Q
    dataBits = nRangeBins * nRamps * nRx * 2 * udreBitsPerSamp;
    % Exponent bits: 8 bits per block exponent
    expBits = nBlocks * nRamps * nRx * 8;
    totalBits = dataBits + expBits;

    compressedData.codesReal       = codesReal;
    compressedData.codesImag       = codesImag;
    compressedData.shiftVals       = shiftVals;
    compressedData.bitProfile      = bitProfile;
    compressedData.blockSize       = blockSize;
    compressedData.udreBitsPerSamp = udreBitsPerSamp;
    compressedData.maxBits         = maxBits;
    compressedData.minBits         = minBits;
    compressedData.totalBits       = totalBits;
    compressedData.inputBits       = inputBits;
    compressedData.CR              = inputBits / totalBits;
    compressedData.scaleFactor     = fx16Data.scaleFactor;
    compressedData.format          = 'rdvle_udre';
end
