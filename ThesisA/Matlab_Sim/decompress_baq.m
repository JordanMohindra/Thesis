function outputData = decompress_baq(compressedData)
% DECOMPRESS_BAQ Decompresses BAQ (Block Floating Point) encoded data.
%   Reconstructs the complex data using the 4-bit codes and the corresponding
%   block exponents.
%
%   Input:
%     compressedData - struct from compress_baq
%
%   Output:
%     outputData - complex double [numRangeBins x numRamps x numRxChannels]

    blockSize = compressedData.blockSize;
    codesReal = double(compressedData.codesReal);
    codesImag = double(compressedData.codesImag);
    shiftVals = double(compressedData.shiftVals);

    [nRangeBins, nRamps, nRx] = size(codesReal);
    nBlocks = ceil(nRangeBins / blockSize);

    reconReal = zeros(nRangeBins, nRamps, nRx);
    reconImag = zeros(nRangeBins, nRamps, nRx);

    for rx = 1:nRx
        for m = 1:nRamps
            for b = 1:nBlocks
                idxStart = (b - 1) * blockSize + 1;
                idxEnd   = min(b * blockSize, nRangeBins);

                shift = shiftVals(b, m, rx);

                reconReal(idxStart:idxEnd, m, rx) = codesReal(idxStart:idxEnd, m, rx) .* (2^shift);
                reconImag(idxStart:idxEnd, m, rx) = codesImag(idxStart:idxEnd, m, rx) .* (2^shift);
            end
        end
    end

    outputData = complex(reconReal, reconImag);
end
