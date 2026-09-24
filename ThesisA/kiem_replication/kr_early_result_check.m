%% KR_EARLY_RESULT_CHECK
%  Why the early Matlab_Sim runs (main_final.log, kiem_final_with_noise.log)
%  gave DRHE CR of about 1.1 at Kiem's noise floor, where Kiem reports 3.25.
%  Two things set the CR on a white-noise scene: the noise floor, and how many
%  FX16 LSBs that noise occupies. This script runs Kiem's Table 3.2 scene at
%  three noise floors with both FX16 scalings:
%    'hw'   - top 16 bits of the 32-bit FFT word (what Kiem's FFT IP core does)
%    'peak' - full-scale ADC sinusoid mapped to 32767 (Matlab_Sim compress_fx16)
%  'peak' puts the same noise 4x (2 bits) higher in the 16-bit word.
%  Output: results/early_result_check.txt

clear;
here = fileparts(mfilename('fullpath')); addpath(here);
outDir = fullfile(here, 'results'); if ~exist(outDir, 'dir'), mkdir(outDir); end
cfg = kr_config('sim');
fid = fopen(fullfile(outDir, 'early_result_check.txt'), 'w');
out = @(varargin) cellfun(@(f) fprintf(f, varargin{:}), {1, fid}, 'UniformOutput', false);
out('FX16 scaling vs compression ratio, Kiem Table 3.2 scene, 1 TX\n');
out('%-5s %8s %14s %10s %9s %6s %7s\n', 'FX16', 'NF dBFS', 'noise std LSB', 'DRHE fix', 'DRHE RLE', 'LPC', 'NoPred');
for mode = {'hw', 'peak'}
    c = cfg; c.fx16Mode = mode{1};
    for nf = [-70.7 -75 -87.9]
        r = kr_run_scene(c, struct('lite', true, 'noiseNF', nf, 'skipRaw', true));
        out('%-5s %8.1f %14.2f %10.2f %9.2f %6.2f %7.2f\n', mode{1}, nf, r.fx16.noiseOnlyStd, ...
            r.metrics.DRHE_fixed.CR, r.metrics.DRHE_RLE.CR, r.metrics.LPC_FFT.CR, r.metrics.NoPred.CR);
    end
end
out('Early Matlab_Sim (peak scaling, white noise, NF -70.7 to -71.0 dBFS): DRHE CR 1.10-1.12.\n');
fclose(fid);
