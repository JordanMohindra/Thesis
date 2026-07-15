function compressedData = compress_rdvle(fx16Data, config)
% COMPRESS_RDVLE Range Dependent Variable Length Encoding (RDVLE).
%   Implements the RDVLE algorithm from Liang Li's thesis
%   "Embedded Data Compression in Automotive FMCW Radar System" (2014).
%
%   RDVLE is a LOSSY compression scheme that exploits the range-power
%   relationship in radar: received power decays as 1/R^4 (monostatic),
%   so distant range bins require fewer bits of precision. The algorithm
%   "cuts" (right-shifts) the least-significant bits from each range bin
%   according to a pre-computed bit-allocation profile.
%
%   The raw R^4 model (40*log10(n)) predicts up to ~96 dB of dynamic range
%   across 256 bins — nearly the full 16-bit container. This is too
%   aggressive: in practice the noise floor is uniform across range and
%   signals use far fewer than 16 effective bits. We scale the R^4 curve
%   so that at most maxBitsToRemove LSBs are cut at the farthest bin,
%   preserving signal quality while achieving meaningful compression.
%
%   Bit allocation per range bin n (scaled):
%     rawDR = 40 * log10(nRangeBins) / 6.02          [total R^4 span in bits]
%     scale = maxBitsToRemove / rawDR
%     bitsToRemove(n) = floor(scale * 40*log10(n) / 6.02)
%     Nb(n) = max(minBits, maxBits - bitsToRemove(n))
%
%   Input:
%     fx16Data - struct from compress_fx16 with .real_part (int16),
%                .imag_part (int16), .scaleFactor
%     config   - struct with .numRamps, .numRxChannels
%
%   Output:
%     compressedData - struct with .codesReal, .codesImag, .bitProfile,
%                      .totalBits, .inputBits, .CR, .scaleFactor

    maxBits         = 16;   % full precision at closest range bin
    minBits         = 4;    % minimum bits at farthest range bin
    maxBitsToRemove = 3;    % max LSBs cut at the farthest range bin

    realData = double(fx16Data.real_part);
    imagData = double(fx16Data.imag_part);

    [nRangeBins, nRamps, nRx] = size(realData);

    % --- Compute bit-allocation profile (one value per range bin) ---
    % Raw R^4 dynamic range across all bins (in bits):
    %   40*log10(nRangeBins) / 6.02
    % We scale this down so the maximum removal equals maxBitsToRemove.
    rawDR_bits = 40 * log10(nRangeBins) / 6.02;  % e.g., ~16 for 256 bins
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

    % --- Apply bit-cutting (right-shift by 16 - Nb bits) ---
    codesReal = zeros(nRangeBins, nRamps, nRx);
    codesImag = zeros(nRangeBins, nRamps, nRx);

    for n = 1:nRangeBins
        shift = maxBits - bitProfile(n);  % number of LSBs to discard
        if shift > 0
            divisor = 2^shift;
            codesReal(n, :, :) = round(realData(n, :, :) / divisor);
            codesImag(n, :, :) = round(imagData(n, :, :) / divisor);
        else
            codesReal(n, :, :) = realData(n, :, :);
            codesImag(n, :, :) = imagData(n, :, :);
        end
    end

    % --- Compute compressed size ---
    % Each sample uses bitProfile(n) bits for I and bitProfile(n) for Q
    inputBits = numel(realData) * 2 * 16;
    totalBits = 0;
    for n = 1:nRangeBins
        totalBits = totalBits + nRamps * nRx * 2 * bitProfile(n);
    end

    compressedData.codesReal    = codesReal;
    compressedData.codesImag    = codesImag;
    compressedData.bitProfile   = bitProfile;
    compressedData.maxBits      = maxBits;
    compressedData.minBits      = minBits;
    compressedData.totalBits    = totalBits;
    compressedData.inputBits    = inputBits;
    compressedData.CR           = inputBits / totalBits;
    compressedData.scaleFactor  = fx16Data.scaleFactor;
    compressedData.format       = 'rdvle';
end
