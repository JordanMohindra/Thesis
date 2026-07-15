function outputData = decompress_rdvle_udre(compressedData)
% DECOMPRESS_RDVLE_UDRE Decompresses combined RDVLE + UDRE encoded data.
%   Inverse of compress_rdvle_udre:
%     Stage 1 (inverse UDRE): Multiply codes by block exponent (2^shift)
%     Stage 2 (inverse RDVLE): Left-shift by the per-range-bin bit cut
%
%   Since both stages discard information (RDVLE cuts LSBs, UDRE requantizes),
%   the reconstruction is lossy — zeros are padded in the discarded positions.
%
%   Input:
%     compressedData - struct from compress_rdvle_udre with .codesReal,
%                      .codesImag, .shiftVals, .bitProfile, .blockSize,
%                      .maxBits, .scaleFactor
%
%   Output:
%     outputData - complex double [numRangeBins x numRamps x numRxChannels]

    blockSize  = compressedData.blockSize;
    maxBits    = compressedData.maxBits;
    bitProfile = compressedData.bitProfile;
    scaleFactor = compressedData.scaleFactor;

    codesReal = compressedData.codesReal;
    codesImag = compressedData.codesImag;
    shiftVals = compressedData.shiftVals;

    [nRangeBins, nRamps, nRx] = size(codesReal);
    nBlocks = ceil(nRangeBins / blockSize);

    % =====================================================================
    % Stage 1 (inverse UDRE): Restore block-scaled values
    % =====================================================================
    udreReal = zeros(nRangeBins, nRamps, nRx);
    udreImag = zeros(nRangeBins, nRamps, nRx);

    for rx = 1:nRx
        for m = 1:nRamps
            for b = 1:nBlocks
                idxStart = (b - 1) * blockSize + 1;
                idxEnd   = min(b * blockSize, nRangeBins);

                blkShift = double(shiftVals(b, m, rx));
                multiplier = 2^blkShift;

                udreReal(idxStart:idxEnd, m, rx) = codesReal(idxStart:idxEnd, m, rx) * multiplier;
                udreImag(idxStart:idxEnd, m, rx) = codesImag(idxStart:idxEnd, m, rx) * multiplier;
            end
        end
    end

    % =====================================================================
    % Stage 2 (inverse RDVLE): Restore bit-cut values
    % =====================================================================
    reconReal = zeros(nRangeBins, nRamps, nRx);
    reconImag = zeros(nRangeBins, nRamps, nRx);

    for n = 1:nRangeBins
        shift = maxBits - bitProfile(n);
        if shift > 0
            multiplier = 2^shift;
            reconReal(n, :, :) = udreReal(n, :, :) * multiplier;
            reconImag(n, :, :) = udreImag(n, :, :) * multiplier;
        else
            reconReal(n, :, :) = udreReal(n, :, :);
            reconImag(n, :, :) = udreImag(n, :, :);
        end
    end

    outputData = complex(reconReal / scaleFactor, reconImag / scaleFactor);
end
