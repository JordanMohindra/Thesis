%% Export Test Vectors for FPGA Verification
%  Exports MATLAB golden reference data for use in Vitis HLS testbenches
%  and FPGA system-level verification.
%
%  This script processes one ColoRadar frame through the full pipeline
%  (preprocess -> window -> FFT -> FX16 -> DRHE) and exports:
%    1. Windowed ADC data (int16, interleaved I/Q per Rx) - FFT IP input
%    2. Range FFT output in FX16 format (int16) - Compression IP input
%    3. DRHE intermediate values (mag/phase predictions, differences)
%    4. DRHE compressed output (Huffman-encoded bitstream info)
%    5. Configuration metadata (JSON)
%
%  Output directory: ./fpga_test_vectors/frame_<N>/
%
%  Usage:
%    export_fpga_test_vectors           % exports frame_0 with defaults
%    export_fpga_test_vectors(3)        % exports frame_3
%    export_fpga_test_vectors(0, 1)     % exports frame_0, TX 1 only

function export_fpga_test_vectors(frameIdx, txSelect)
    if nargin < 1, frameIdx = 0; end
    if nargin < 2, txSelect = 1:12; end

    %% --- Configuration ---
    FX16_ENOB   = 16;
    REMOVE_DC   = true;

    %% --- Locate frame file ---
    dataDir = fullfile(fileparts(mfilename('fullpath')), '..', '..', ...
                       'Jordan''s Thesis', 'cascade', 'adc_samples', 'data');
    binFile = fullfile(dataDir, sprintf('frame_%d.bin', frameIdx));

    if exist(binFile, 'file') ~= 2
        error('Frame file not found: %s', binFile);
    end

    %% --- Create output directory ---
    outDir = fullfile(fileparts(mfilename('fullpath')), 'fpga_test_vectors', ...
                      sprintf('frame_%d', frameIdx));
    if ~exist(outDir, 'dir')
        mkdir(outDir);
    end
    fprintf('Exporting test vectors to: %s\n', outDir);

    %% --- Load frame ---
    opts = struct('txSelect', txSelect, 'removeDC', REMOVE_DC, ...
                  'fx16EffectiveBits', FX16_ENOB);
    [cube, config, ~] = loadColoRadarFrame(binFile, opts);

    nSamp   = config.numSamples;
    nRamps  = config.numRamps;
    nRx     = config.numRxChannels;

    %% ========================================================================
    %  EXPORT 1: Windowed ADC data (FFT IP core input)
    %  Format: int16, interleaved as [Re_rx0, Im_rx0, Re_rx1, Im_rx1, ...]
    %  per sample, for each ramp. This matches the Xilinx FFT IP 4-channel
    %  interleaved format.
    %  ========================================================================
    fprintf('  [1/5] Exporting windowed ADC data...\n');

    preprocessedData = preprocessing(cube, config);

    % Quantize windowed data to int16 (matching Kiem's approach)
    % The data is already shifted to 32-bit full-scale by preprocessing,
    % so we need to scale back to int16 range
    maxVal = max(abs(preprocessedData(:)));
    if maxVal == 0, maxVal = 1; end
    adcScale = 32767 / maxVal;
    windowedInt16 = int16(round(preprocessedData * adcScale));

    % Write in interleaved format: for each ramp, interleave all Rx channels
    % Format per FFT transaction: [Re_rx0 Im_rx0 Re_rx1 Im_rx1 ... Re_rxN Im_rxN]
    fid = fopen(fullfile(outDir, 'windowed_adc_int16.bin'), 'w');
    for m = 1:nRamps
        for n = 1:nSamp
            for rx = 1:nRx
                % Real-valued input: imaginary = 0
                fwrite(fid, real(windowedInt16(n, m, rx)), 'int16');
                fwrite(fid, int16(0), 'int16');  % imag = 0 for real ADC
            end
        end
    end
    fclose(fid);

    %% ========================================================================
    %  EXPORT 2: Range FFT output in FX16 (Compression IP core input)
    %  This is the direct input to the DRHE compression core.
    %  Format: int16 pairs [Re, Im] interleaved across Rx channels per bin.
    %  ========================================================================
    fprintf('  [2/5] Exporting FX16 range FFT data...\n');

    rangeFFTData = rangeFFT(preprocessedData, config);
    compressedFX16 = compress_fx16(rangeFFTData, config);

    nRangeBins = size(compressedFX16.real_part, 1);

    % Write as flat binary: for each ramp, for each range bin, interleave Rx
    % This matches the AXI Stream format: one transaction = one range bin
    % across all Rx channels [Re_rx0 Im_rx0 Re_rx1 Im_rx1 ...]
    fid = fopen(fullfile(outDir, 'fx16_fft_output.bin'), 'w');
    for m = 1:nRamps
        for n = 1:nRangeBins
            for rx = 1:nRx
                fwrite(fid, compressedFX16.real_part(n, m, rx), 'int16');
                fwrite(fid, compressedFX16.imag_part(n, m, rx), 'int16');
            end
        end
    end
    fclose(fid);

    % Also write non-interleaved for easier MATLAB re-loading
    fid = fopen(fullfile(outDir, 'fx16_real.bin'), 'w');
    fwrite(fid, compressedFX16.real_part(:), 'int16');
    fclose(fid);

    fid = fopen(fullfile(outDir, 'fx16_imag.bin'), 'w');
    fwrite(fid, compressedFX16.imag_part(:), 'int16');
    fclose(fid);

    %% ========================================================================
    %  EXPORT 3: DRHE intermediate values (for debugging the HLS pipeline)
    %  Exports per-ramp magnitude, phase, predictions, and differences.
    %  ========================================================================
    fprintf('  [3/5] Exporting DRHE intermediate values...\n');

    alpha = 0.6;
    beta  = 0.4;

    realData = double(compressedFX16.real_part);
    imagData = double(compressedFX16.imag_part);

    % Preallocate intermediate arrays
    all_mag        = zeros(nRangeBins, nRamps, nRx);
    all_phase      = zeros(nRangeBins, nRamps, nRx);
    all_mag_pred   = zeros(nRangeBins, nRamps, nRx);
    all_phase_pred = zeros(nRangeBins, nRamps, nRx);
    all_pred_re    = zeros(nRangeBins, nRamps, nRx);
    all_pred_im    = zeros(nRangeBins, nRamps, nRx);
    all_diff_re    = zeros(nRangeBins, nRamps, nRx);
    all_diff_im    = zeros(nRangeBins, nRamps, nRx);
    all_s4_re      = zeros(nRangeBins, nRamps, nRx);
    all_s4_im      = zeros(nRangeBins, nRamps, nRx);

    for rx = 1:nRx
        prev_mag_pred    = zeros(nRangeBins, 1);
        prev_mag         = zeros(nRangeBins, 1);
        prev_phase_pred  = zeros(nRangeBins, 1);
        prev_phase       = zeros(nRangeBins, 1);
        prev_prev_phase  = zeros(nRangeBins, 1);

        for m = 1:nRamps
            re = realData(:, m, rx);
            im = imagData(:, m, rx);

            curr_mag   = sqrt(re.^2 + im.^2);
            curr_phase = atan2(im, re);

            mag_pred   = alpha * prev_mag_pred + (1 - alpha) * prev_mag;
            phase_pred = beta * prev_phase_pred + (2 - beta) * prev_phase - prev_prev_phase;

            phase_pred(phase_pred > pi)  = phase_pred(phase_pred > pi)  - 2*pi;
            phase_pred(phase_pred < -pi) = phase_pred(phase_pred < -pi) + 2*pi;

            pred_re = round(mag_pred .* cos(phase_pred));
            pred_im = round(mag_pred .* sin(phase_pred));

            d_re = mod(re - pred_re + 32768, 65536) - 32768;  % wrap_int16
            d_im = mod(im - pred_im + 32768, 65536) - 32768;

            % Compute S4 regions
            s4_re = compute_s4(d_re);
            s4_im = compute_s4(d_im);

            % Store intermediates
            all_mag(:, m, rx)        = curr_mag;
            all_phase(:, m, rx)      = curr_phase;
            all_mag_pred(:, m, rx)   = mag_pred;
            all_phase_pred(:, m, rx) = phase_pred;
            all_pred_re(:, m, rx)    = pred_re;
            all_pred_im(:, m, rx)    = pred_im;
            all_diff_re(:, m, rx)    = d_re;
            all_diff_im(:, m, rx)    = d_im;
            all_s4_re(:, m, rx)      = s4_re;
            all_s4_im(:, m, rx)      = s4_im;

            % Update state
            prev_prev_phase = prev_phase;
            prev_phase      = curr_phase;
            prev_phase_pred = phase_pred;
            prev_mag        = curr_mag;
            prev_mag_pred   = mag_pred;
        end
    end

    % Save intermediates as double-precision binary (for HLS testbench comparison)
    save(fullfile(outDir, 'drhe_intermediates.mat'), ...
         'all_mag', 'all_phase', 'all_mag_pred', 'all_phase_pred', ...
         'all_pred_re', 'all_pred_im', 'all_diff_re', 'all_diff_im', ...
         'all_s4_re', 'all_s4_im', 'alpha', 'beta');

    % Also export differences as int16 binary (main test vector for HLS)
    fid = fopen(fullfile(outDir, 'drhe_diff_real.bin'), 'w');
    fwrite(fid, int16(all_diff_re(:)), 'int16');
    fclose(fid);

    fid = fopen(fullfile(outDir, 'drhe_diff_imag.bin'), 'w');
    fwrite(fid, int16(all_diff_im(:)), 'int16');
    fclose(fid);

    %% ========================================================================
    %  EXPORT 4: Full DRHE compressed output (Huffman-encoded metrics)
    %  ========================================================================
    fprintf('  [4/5] Exporting DRHE compressed output...\n');

    compressedDRHE = compress_drhe(compressedFX16, config);

    % Export S4 regions and bit counts per sample (for Huffman verification)
    huffLengths = [4, 3, 2, 2, 2, 5, 6, 7, 8, 9, 10, 11, 14, 14, 13, 12];

    % Compute per-sample bit counts for the entire frame
    bits_re = compute_bits_per_sample(all_diff_re(:), huffLengths);
    bits_im = compute_bits_per_sample(all_diff_im(:), huffLengths);

    fid = fopen(fullfile(outDir, 'drhe_bits_per_sample_re.bin'), 'w');
    fwrite(fid, uint8(bits_re), 'uint8');
    fclose(fid);

    fid = fopen(fullfile(outDir, 'drhe_bits_per_sample_im.bin'), 'w');
    fwrite(fid, uint8(bits_im), 'uint8');
    fclose(fid);

    % Export S4 regions as uint8
    fid = fopen(fullfile(outDir, 'drhe_s4_re.bin'), 'w');
    fwrite(fid, uint8(all_s4_re(:)), 'uint8');
    fclose(fid);

    fid = fopen(fullfile(outDir, 'drhe_s4_im.bin'), 'w');
    fwrite(fid, uint8(all_s4_im(:)), 'uint8');
    fclose(fid);

    %% ========================================================================
    %  EXPORT 5: Configuration metadata (JSON)
    %  ========================================================================
    fprintf('  [5/5] Exporting configuration metadata...\n');

    metadata = struct();
    metadata.frameIndex       = frameIdx;
    metadata.numSamples       = nSamp;
    metadata.numRangeBins     = nRangeBins;
    metadata.numRamps         = nRamps;
    metadata.numRxChannels    = nRx;
    metadata.bitWidth         = config.bitWidth;
    metadata.fx16ScaleFactor  = compressedFX16.scaleFactor;
    metadata.fx16EffectiveBits = FX16_ENOB;
    metadata.drhe_alpha       = alpha;
    metadata.drhe_beta        = beta;
    metadata.drhe_CR          = compressedDRHE.CR;
    metadata.drhe_totalBits   = compressedDRHE.totalBits;
    metadata.drhe_inputBits   = compressedDRHE.inputBits;
    metadata.huffmanLengths   = huffLengths;
    metadata.totalSamples     = numel(all_diff_re);

    % Write as JSON
    jsonStr = jsonencode(metadata, 'PrettyPrint', true);
    fid = fopen(fullfile(outDir, 'config.json'), 'w');
    fprintf(fid, '%s', jsonStr);
    fclose(fid);

    %% --- Summary ---
    fprintf('\n========================================\n');
    fprintf('  Export complete for frame_%d\n', frameIdx);
    fprintf('  Output directory: %s\n', outDir);
    fprintf('  Dimensions: %d range bins x %d ramps x %d Rx\n', nRangeBins, nRamps, nRx);
    fprintf('  FX16 scale factor: %.6f\n', compressedFX16.scaleFactor);
    fprintf('  DRHE CR: %.2f\n', compressedDRHE.CR);
    fprintf('  Total samples: %d\n', numel(all_diff_re));
    fprintf('========================================\n');
    fprintf('\n  Files exported:\n');
    fprintf('    windowed_adc_int16.bin     - Windowed ADC (FFT input)\n');
    fprintf('    fx16_fft_output.bin        - FX16 FFT output, interleaved (compression IP input)\n');
    fprintf('    fx16_real.bin / fx16_imag.bin - FX16 FFT output, non-interleaved\n');
    fprintf('    drhe_intermediates.mat     - All DRHE intermediate values\n');
    fprintf('    drhe_diff_real/imag.bin    - DRHE difference values (int16)\n');
    fprintf('    drhe_bits_per_sample_*.bin - Bits per sample after Huffman (uint8)\n');
    fprintf('    drhe_s4_re/im.bin          - S4 regions per sample (uint8)\n');
    fprintf('    config.json                - Configuration metadata\n');
end


function s4 = compute_s4(values)
% COMPUTE_S4 Compute the S4 region for each value (used in Huffman encoding).
    absVal = abs(values);
    s4 = zeros(size(values));
    s4(absVal == 0) = 0;
    nonzero = absVal > 0;
    s4(nonzero) = floor(log2(absVal(nonzero))) + 1;
    s4 = min(s4, 15);
end


function bits = compute_bits_per_sample(values, huffLengths)
% COMPUTE_BITS_PER_SAMPLE Total bits needed per sample (Huffman + APPEND).
    s4 = compute_s4(values);
    bits = zeros(size(values));
    for i = 0:15
        mask = (s4 == i);
        bits(mask) = huffLengths(i + 1) + i;
    end
end
