function outputData = decompress_rdvle(compressedData)
% DECOMPRESS_RDVLE Decompresses RDVLE-encoded data.
%   Inverse of compress_rdvle: restores the bit-cut samples by left-shifting
%   (multiplying by 2^shift) to reconstruct 16-bit values. Since the LSBs
%   were discarded during compression, zeros are padded — this is the lossy
%   aspect of RDVLE.
%
%   Input:
%     compressedData - struct from compress_rdvle with .codesReal, .codesImag,
%                      .bitProfile, .maxBits, .scaleFactor
%
%   Output:
%     outputData - complex double [numRangeBins x numRamps x numRxChannels]

    maxBits    = compressedData.maxBits;
    bitProfile = compressedData.bitProfile;
    scaleFactor = compressedData.scaleFactor;

    codesReal = compressedData.codesReal;
    codesImag = compressedData.codesImag;

    [nRangeBins, nRamps, nRx] = size(codesReal);

    reconReal = zeros(nRangeBins, nRamps, nRx);
    reconImag = zeros(nRangeBins, nRamps, nRx);

    for n = 1:nRangeBins
        shift = maxBits - bitProfile(n);
        if shift > 0
            multiplier = 2^shift;
            reconReal(n, :, :) = codesReal(n, :, :) * multiplier;
            reconImag(n, :, :) = codesImag(n, :, :) * multiplier;
        else
            reconReal(n, :, :) = codesReal(n, :, :);
            reconImag(n, :, :) = codesImag(n, :, :);
        end
    end

    outputData = complex(reconReal / scaleFactor, reconImag / scaleFactor);
end
