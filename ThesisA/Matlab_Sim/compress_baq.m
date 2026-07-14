function compressedData = compress_baq(rangeFFTData, config)
% COMPRESS_BAQ Block Adaptive Quantization (Block Floating Point style)
%   Divides data into blocks along the range dimension.
%   Finds the maximum amplitude in each block and determines a common exponent
%   (shift value) to quantize the I and Q components to 4 bits each.
%
%   Input:
%     rangeFFTData - complex double [numRangeBins x numRamps x numRxChannels]
%     config       - (unused for BFP calculation, included for API consistency)
%
%   Output:
%     compressedData - struct with quantized data and block exponents

    blockSize = 16;
    bitsPerSample = 4;
    maxQuantVal = 2^(bitsPerSample - 1) - 1; % For 4 bits, max val is 7, min is -8

    realData = real(rangeFFTData);
    imagData = imag(rangeFFTData);

    [nRangeBins, nRamps, nRx] = size(rangeFFTData);
    nBlocks = ceil(nRangeBins / blockSize);

    % Initialize outputs
    codesReal = int8(zeros(nRangeBins, nRamps, nRx));
    codesImag = int8(zeros(nRangeBins, nRamps, nRx));
    shiftVals = uint8(zeros(nBlocks, nRamps, nRx));

    for rx = 1:nRx
        for m = 1:nRamps
            for b = 1:nBlocks
                idxStart = (b - 1) * blockSize + 1;
                idxEnd   = min(b * blockSize, nRangeBins);

                blockReal = realData(idxStart:idxEnd, m, rx);
                blockImag = imagData(idxStart:idxEnd, m, rx);

                % Find max absolute value in the block (both I and Q)
                maxVal = max(max(abs(blockReal)), max(abs(blockImag)));

                if maxVal == 0
                    shift = 0;
                else
                    % We want: maxVal / (2^shift) <= maxQuantVal
                    % 2^shift >= maxVal / maxQuantVal
                    % shift >= log2(maxVal / maxQuantVal)
                    shift = max(0, ceil(log2(maxVal / maxQuantVal)));
                end

                % Quantize
                qReal = round(blockReal ./ (2^shift));
                qImag = round(blockImag ./ (2^shift));

                % Clip to valid range just in case (shouldn't exceed based on shift logic)
                qReal = max(min(qReal, maxQuantVal), -maxQuantVal - 1);
                qImag = max(min(qImag, maxQuantVal), -maxQuantVal - 1);

                codesReal(idxStart:idxEnd, m, rx) = int8(qReal);
                codesImag(idxStart:idxEnd, m, rx) = int8(qImag);
                shiftVals(b, m, rx) = uint8(shift);
            end
        end
    end

    inputBits = nRangeBins * nRamps * nRx * 2 * 16; % Assumes 16-bit uncompressed input

    % Data bits: 4 bits per I, 4 bits per Q
    dataBits = nRangeBins * nRamps * nRx * 2 * bitsPerSample;
    % Exponent bits: assume 8 bits per block exponent
    expBits = nBlocks * nRamps * nRx * 8;
    totalBits = dataBits + expBits;

    compressedData.codesReal = codesReal;
    compressedData.codesImag = codesImag;
    compressedData.shiftVals = shiftVals;
    compressedData.blockSize = blockSize;
    compressedData.totalBits = totalBits;
    compressedData.inputBits = inputBits;
    compressedData.CR = inputBits / totalBits;
    compressedData.format = 'baq';
end
