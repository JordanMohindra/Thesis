%% Radar Data Compression Simulation - REAL CAPTURE
%  Runs a real recorded Ancortek FMCW capture (target + background) through the
%  SAME Kiem compression workflow used for the synthetic scenes
%  (Reference / FP16 / FX16 / DRHE, Figure 3.1) and produces the SAME graphs
%  (Figures 3.5-3.7, including the 3D range-Doppler "cloud") -- but drawn against
%  real range (m) and velocity (m/s) so the plots show the true physical
%  placement of each object.
%
%  HOW IT WORKS
%    loadRealRadarCube.m reads the .bin files, demuxes the 2Tx/4Rx I/Q exactly
%    like read_radar_data_fmcw.m / SDRadar.m, and assembles a complex ADC cube
%    [numSamples x numRamps x numRxChannels] -- the same shape generateSyntheticADC
%    produces. runCompressionSim.m then accepts that cube directly (4th argument)
%    and runs the unchanged pipeline.
%
%  BACKGROUND SUBTRACTION
%    Subtracting the averaged background sweep is a LINEAR operation in the raw
%    ADC domain, so it commutes with the range FFT (identical to subtracting the
%    background range profile). It reveals the moving target by removing static
%    clutter -- but that clutter is exactly the slow-time-correlated energy DRHE
%    compresses best, so removing it LOWERS the DRHE compression ratio. This
%    script therefore runs the capture BOTH ways and prints the two compression
%    tables side by side, then uses the background-subtracted data for the
%    object-placement graphs.

clear; clc; close all;

%% ============ CONFIGURATION (edit these) ==========================
% Capture pair to process. Files are matched by the descriptive token in the
% Ancortek file name; the actual radar parameters are read from each .bin header.
CAPTURE = '1000_256';        % '1000_256' | '128_64' | 'custom'

% For CAPTURE = 'custom', set these two paths directly (or leave '' to be
% prompted with a file picker).
CUSTOM_TGT = '';
CUSTOM_BG  = '';

FX16_ENOB     = 16;          % effective FX16 bits (16 = no extra quantisation loss)
RANGE_MAX_PLOT = 2;          % [m] range axis cap for the graphs
VEL_MAX_PLOT   = [];         % [m/s] velocity axis cap ([] = radar Nyquist)
SHOW_RAW_PLOTS = false;      % also plot the clutter-kept (raw) 3D image
% ===================================================================

%% --- locate the data files ---------------------------------------
dataDir = fullfile(fileparts(mfilename('fullpath')), '..', '..');   % repo root
switch CAPTURE
    case '1000_256'
        tgtFile = fullfile(dataDir, 'Jun_24_2026_14_12_05_611_2_targets_1000_256.bin');
        bgFile  = fullfile(dataDir, 'Jun_24_2026_14_14_42_355_1000_BKG.bin');
    case '128_64'
        tgtFile = fullfile(dataDir, 'Jun_24_2026_14_12_05_611_2_targets_128_64.bin');
        bgFile  = fullfile(dataDir, 'Jun_24_2026_14_14_42_355_128_BKG.bin');
    case 'custom'
        tgtFile = CUSTOM_TGT;
        bgFile  = CUSTOM_BG;
    otherwise
        error('main_simulation_real:capture', 'Unknown CAPTURE "%s".', CAPTURE);
end
if ~isempty(tgtFile) && exist(tgtFile, 'file') ~= 2
    warning('Target file not found (%s); a file picker will open.', tgtFile);
    tgtFile = '';
end
if ~isempty(bgFile) && exist(bgFile, 'file') ~= 2
    warning('Background file not found (%s); a file picker will open.', bgFile);
    bgFile = '';
end

fprintf('================================================================\n');
fprintf('  RADAR DATA COMPRESSION SIMULATION - REAL CAPTURE (%s)\n', CAPTURE);
fprintf('================================================================\n');

%% --- load both variants (raw and background-subtracted) ----------
commonOpts = struct('fx16EffectiveBits', FX16_ENOB, ...
                    'rangeMaxPlot', RANGE_MAX_PLOT, 'velMaxPlot', VEL_MAX_PLOT);

% (1) RAW: clutter kept (this is what the radar would actually store/compress)
optsRaw = commonOpts; optsRaw.bgSubtract = false;
[cubeRaw, cfgRaw, axRaw] = loadRealRadarCube(tgtFile, bgFile, optsRaw);

% (2) BG-SUBTRACTED: clutter removed (best for revealing object placement).
%     Force the SAME bitWidth so the two compression results are comparable.
optsBS = commonOpts; optsBS.bgSubtract = true; optsBS.bitWidth = cfgRaw.bitWidth;
[cubeBS, cfgBS, axBS] = loadRealRadarCube(tgtFile, bgFile, optsBS);

%% --- run the compression workflow on each --------------------------
PrefRaw = computeFullScaleRefPower(cfgRaw);
PrefBS  = computeFullScaleRefPower(cfgBS);

resRaw = runCompressionSim(cfgRaw, PrefRaw, 'real - clutter kept (raw)',        cubeRaw);
resBS  = runCompressionSim(cfgBS,  PrefBS,  'real - background subtracted',     cubeBS);

%% --- side-by-side compression comparison ---------------------------
fprintf('\n================================================================\n');
fprintf('  EFFECT OF BACKGROUND SUBTRACTION ON COMPRESSION\n');
fprintf('  (Algorithm | CR | FN%% | FP%% | NF dBFS | SNR dB)\n');
fprintf('================================================================\n');
printRow = @(name, m) fprintf('  %-6s %6.2f %7.2f %7.2f %11.3f %9.3f\n', ...
    name, m.CR, m.FN_pct, m.FP_pct, m.NF_dBFS, m.SNR_dB);

fprintf('\n  RAW (clutter kept):\n');
printRow('FP16', resRaw.metricsFP16);
printRow('FX16', resRaw.metricsFX16);
printRow('DRHE', resRaw.metricsDRHE);

fprintf('\n  BACKGROUND SUBTRACTED:\n');
printRow('FP16', resBS.metricsFP16);
printRow('FX16', resBS.metricsFX16);
printRow('DRHE', resBS.metricsDRHE);

fprintf('\n  DRHE compression ratio: %.2f (raw) -> %.2f (bg-subtracted).\n', ...
    resRaw.metricsDRHE.CR, resBS.metricsDRHE.CR);
fprintf('  Removing the static clutter strips out the slow-time-correlated\n');
fprintf('  energy DRHE predicts best, so the bg-subtracted CR is the lower bound;\n');
fprintf('  the raw CR is what the radar would achieve storing the full scene.\n');

%% --- graphs (object placement uses the background-subtracted data) --
plotProcessingStages(resBS.rangeFFTData, resBS.dopplerFFTRef, resBS.rdMapRef, cfgBS, axBS);
plotCompressionComparison(resBS.rdMapFP16, resBS.rdMapFX16, cfgBS, PrefBS, axBS);

if SHOW_RAW_PLOTS
    plotProcessingStages(resRaw.rangeFFTData, resRaw.dopplerFFTRef, resRaw.rdMapRef, cfgRaw, axRaw);
end

fprintf('\n================================================================\n');
fprintf('  REAL-CAPTURE RUN COMPLETE\n');
fprintf('================================================================\n');
