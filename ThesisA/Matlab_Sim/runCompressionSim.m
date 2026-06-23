function results = runCompressionSim(config, fullScaleRefPower, label)
% RUNCOMPRESSIONSIM Runs the full Kiem compression workflow on one scene.
%   Executes the four processing paths from Figure 3.1 (Reference / FP16 /
%   FX16 / DRHE), evaluates the Section 3.4.2 metrics, prints a results table
%   and returns everything needed for plotting and comparison.
%
%   Input:
%     config            - scene/pipeline configuration struct
%     fullScaleRefPower - 0 dBFS reference power (computeFullScaleRefPower)
%     label             - short string naming the scene (for printouts)
%
%   Output:
%     results - struct with metrics, range-Doppler maps, detection lists and
%               the DRHE compression record.

    if nargin < 3, label = 'scene'; end

    fprintf('\n================================================================\n');
    fprintf('  SCENE: %s\n', upper(label));
    fprintf('================================================================\n');

    % --- Step 1-3: ADC -> Preprocessing -> Range FFT ---
    rawADC           = generateSyntheticADC(config);
    preprocessedData = preprocessing(rawADC, config);
    rangeFFTData     = rangeFFT(preprocessedData, config);

    % --- Path A: double-precision reference ---
    [detListRef, rdMapRef, dopplerFFTRef] = secondStageProcessing(rangeFFTData, config);

    % --- Path B: FP16 ---
    compressedFP16   = compress_fp16(rangeFFTData);
    decompressedFP16 = decompress_fp16(compressedFP16);
    [detListFP16, rdMapFP16, ~] = secondStageProcessing(decompressedFP16, config);

    % --- Path C: FX16 ---
    compressedFX16   = compress_fx16(rangeFFTData, config);
    decompressedFX16 = decompress_fx16(compressedFX16);
    [detListFX16, rdMapFX16, ~] = secondStageProcessing(decompressedFX16, config);

    % --- Path D: DRHE (lossless on the FX16 codes) ---
    compressedDRHE   = compress_drhe(compressedFX16, config);
    decompressedDRHE = decompress_drhe(compressedDRHE);
    [detListDRHE, rdMapDRHE, ~] = secondStageProcessing(decompressedDRHE, config);

    % --- Metrics ---
    metricsFP16 = evaluateMetrics(detListRef, detListFP16, rdMapRef, rdMapFP16, 1.0, fullScaleRefPower);
    metricsFX16 = evaluateMetrics(detListRef, detListFX16, rdMapRef, rdMapFX16, 1.0, fullScaleRefPower);
    metricsDRHE = evaluateMetrics(detListRef, detListDRHE, rdMapRef, rdMapDRHE, compressedDRHE.CR, fullScaleRefPower);

    % --- Results table ---
    fprintf('  Reference detections: %d\n', sum(detListRef(:)));
    fprintf('  %-10s %6s %8s %8s %14s %10s\n', 'Algorithm', 'CR', 'FN (%)', 'FP (%)', 'NF est.(dBFS)', 'SNR (dB)');
    fprintf('  %-10s %6s %8s %8s %14s %10s\n', '---------', '------', '------', '------', '-------------', '--------');
    fprintf('  %-10s %6.2f %8.2f %8.2f %14.3f %10.3f\n', 'FP16', metricsFP16.CR, metricsFP16.FN_pct, metricsFP16.FP_pct, metricsFP16.NF_dBFS, metricsFP16.SNR_dB);
    fprintf('  %-10s %6.2f %8.2f %8.2f %14.3f %10.3f\n', 'FX16', metricsFX16.CR, metricsFX16.FN_pct, metricsFX16.FP_pct, metricsFX16.NF_dBFS, metricsFX16.SNR_dB);
    fprintf('  %-10s %6.2f %8.2f %8.2f %14.3f %10.3f\n', 'DRHE', metricsDRHE.CR, metricsDRHE.FN_pct, metricsDRHE.FP_pct, metricsDRHE.NF_dBFS, metricsDRHE.SNR_dB);

    % --- Pack results ---
    results.label         = label;
    results.config        = config;
    results.metricsFP16   = metricsFP16;
    results.metricsFX16   = metricsFX16;
    results.metricsDRHE   = metricsDRHE;
    results.refDetections = sum(detListRef(:));
    results.rangeFFTData  = rangeFFTData;
    results.dopplerFFTRef = dopplerFFTRef;
    results.rdMapRef      = rdMapRef;
    results.rdMapFP16     = rdMapFP16;
    results.rdMapFX16     = rdMapFX16;
    results.rdMapDRHE     = rdMapDRHE;
    results.detListRef    = detListRef;
    results.compressedDRHE = compressedDRHE;
    results.compressedFX16 = compressedFX16;
end
