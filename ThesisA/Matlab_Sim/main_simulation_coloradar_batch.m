%% Radar Data Compression Simulation - COLORADAR CASCADE (Batch Mode)
%  Iterates through multiple frames in the ColoRadar dataset and computes
%  global average metrics (CR, FN%, FP%, NF, SNR) for all algorithms.

clear; clc; close all;

%% ============ CONFIGURATION (edit these) ==========================
MAX_FRAMES  = 1;             % Maximum number of frames to process (use inf for all)
if ~isempty(getenv('DRHE_MAX_FRAMES'))   % optional override for scripted runs
    MAX_FRAMES = str2double(getenv('DRHE_MAX_FRAMES'));
end
TX_SELECT   = 1:12;           % which TX antennas to use (1:12 = all)
FX16_ENOB   = 16;             % effective FX16 bits (16 = lossless container)
REMOVE_DC   = true;           % subtract per-ramp mean per channel
RANGE_MAX_PLOT = 25;          % [m] range axis cap for plots
VEL_MAX_PLOT   = [];          % [m/s] velocity axis cap ([] = radar Nyquist)
% ===================================================================

%% --- locate the frames --------------------------------------------
candidatePaths = { ...
    'D:\Jordan''s Thesis\cascade\adc_samples\data', ...
    fullfile(fileparts(mfilename('fullpath')), '..', '..', '..', 'Jordan''s Thesis', 'cascade', 'adc_samples', 'data'), ...
    fullfile(fileparts(mfilename('fullpath')), '..', '..', 'Jordan''s Thesis', 'cascade', 'adc_samples', 'data'), ...
    'C:\Users\mohin\Downloads\12_21_2020_ec_hallways_run4\12_21_2020_ec_hallways_run4\cascade\adc_samples\data' ...
};

dataDir = '';
for i = 1:length(candidatePaths)
    if exist(candidatePaths{i}, 'dir')
        files = dir(fullfile(candidatePaths{i}, 'frame_*.bin'));
        if ~isempty(files)
            dataDir = candidatePaths{i};
            frameFiles = files;
            break;
        end
    end
end

if isempty(dataDir)
    error('No frame files found in candidate directories.');
end
numAvailableFrames = length(frameFiles);

numFramesToProcess = min(MAX_FRAMES, numAvailableFrames);

fprintf('================================================================\n');
fprintf('  BATCH SIMULATION - COLORADAR CASCADE\n');
fprintf('  Processing %d frames (out of %d available)...\n', numFramesToProcess, numAvailableFrames);
fprintf('================================================================\n');

%% --- Initialize accumulators --------------------------------------
algorithms = {'FP16', 'DRHEfp16', 'FX16', 'DRHE', 'BAQ', 'RDVLE', 'RDVLE_UDRE', 'LPC_Huffman'};
numAlgos = length(algorithms);

% Struct to hold global sums
globalMetrics = struct();
for i = 1:numAlgos
    algo = algorithms{i};
    globalMetrics.(algo) = struct('totalFN', 0, 'totalFP', 0, 'totalTestDet', 0, 'sumCR', 0, 'sumNF', 0, 'sumSNR', 0);
end
globalTotalRefDetections = 0;

%% --- Batch Processing Loop ----------------------------------------
opts = struct( ...
    'txSelect',          TX_SELECT, ...
    'removeDC',          REMOVE_DC, ...
    'fx16EffectiveBits', FX16_ENOB, ...
    'rangeMaxPlot',      RANGE_MAX_PLOT, ...
    'velMaxPlot',        VEL_MAX_PLOT);

for f = 1:numFramesToProcess
    frameIdx = f - 1;
    binFile = fullfile(dataDir, sprintf('frame_%d.bin', frameIdx));
    
    if exist(binFile, 'file') ~= 2
        fprintf('  Skipping missing frame_%d.bin...\n', frameIdx);
        continue;
    end
    
    fprintf('  Processing frame_%d.bin (%d/%d)... ', frameIdx, f, numFramesToProcess);
    
    % Load frame
    try
        [cube, config, axesInfo] = loadColoRadarFrame(binFile, opts);
        fullScaleRefPower = computeFullScaleRefPower(config);
        
        % Run simulation quietly to avoid spamming the console
        evalc('results = runCompressionSim(config, fullScaleRefPower, sprintf(''frame_%d'', frameIdx), cube);');
        
        % Accumulate reference detections
        refDet = results.refDetections;
        globalTotalRefDetections = globalTotalRefDetections + refDet;
        
        % Accumulate metrics for each algorithm
        for i = 1:numAlgos
            algo = algorithms{i};
            m = results.(['metrics' algo]);
            
            % Convert percentages back to absolute counts
            % FN_pct = FN / refDet * 100  =>  FN = FN_pct/100 * refDet
            fn_count = round((m.FN_pct / 100) * refDet);
            
            % FP_pct = FP / testDet * 100  =>  need testDet to recover FP
            % TP = refDet - fn_count
            tp_count = refDet - fn_count;
            if m.FP_pct < 100
                % testDet = TP / (1 - FP_pct/100)
                testDet = tp_count / (1 - m.FP_pct / 100);
                fp_count = round(testDet - tp_count);
            else
                fp_count = 0;
            end
            
            globalMetrics.(algo).totalFN = globalMetrics.(algo).totalFN + fn_count;
            globalMetrics.(algo).totalFP = globalMetrics.(algo).totalFP + fp_count;
            globalMetrics.(algo).totalTestDet = globalMetrics.(algo).totalTestDet + tp_count + fp_count;
            globalMetrics.(algo).sumCR   = globalMetrics.(algo).sumCR   + m.CR;
            globalMetrics.(algo).sumNF   = globalMetrics.(algo).sumNF   + m.NF_dBFS;
            globalMetrics.(algo).sumSNR  = globalMetrics.(algo).sumSNR  + m.SNR_dB;
        end
        fprintf('Done. (%d ref detections)\n', refDet);
        
    catch ME
        fprintf('ERROR: %s\n', ME.message);
    end
end

%% --- Compute Final Averages ---
fprintf('\n================================================================\n');
fprintf('  BATCH SIMULATION COMPLETE - GLOBAL AVERAGES (%d FRAMES)\n', numFramesToProcess);
fprintf('  Total Reference Detections Across All Frames: %d\n', globalTotalRefDetections);
fprintf('================================================================\n');

fprintf('  %-10s %6s %8s %8s %14s %10s\n', 'Algorithm', 'Avg CR', 'FN (%)', 'FP (%)', 'Avg NF (dBFS)', 'Avg SNR (dB)');
fprintf('  %-10s %6s %8s %8s %14s %10s\n', '---------', '------', '------', '------', '-------------', '--------');

for i = 1:numAlgos
    algo = algorithms{i};
    g = globalMetrics.(algo);
    
    avgCR  = g.sumCR / numFramesToProcess;
    avgNF  = g.sumNF / numFramesToProcess;
    avgSNR = g.sumSNR / numFramesToProcess;
    
    if globalTotalRefDetections > 0
        globalFN_pct = (g.totalFN / globalTotalRefDetections) * 100;
    else
        globalFN_pct = 0;
    end
    
    if g.totalTestDet > 0
        globalFP_pct = (g.totalFP / g.totalTestDet) * 100;
    else
        globalFP_pct = 0;
    end
    
    fprintf('  %-10s %6.2f %8.2f %8.2f %14.3f %10.3f\n', ...
        algo, avgCR, globalFN_pct, globalFP_pct, avgNF, avgSNR);
end

fprintf('\n  Interpretation:\n');
fprintf('   * These metrics represent the true global performance over a sequence of frames.\n');
fprintf('   * False Positives and False Negatives are calculated as a percentage of the TOTAL\n');
fprintf('     detections across the entire run, preventing single-frame anomalies from skewing results.\n');
