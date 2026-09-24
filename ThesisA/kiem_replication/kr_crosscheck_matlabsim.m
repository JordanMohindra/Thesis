%% KR_CROSSCHECK_MATLABSIM
%  Verification only. This is the ONE file in this folder that touches
%  Matlab_Sim: it runs the thesis's own DRHE (Matlab_Sim/compress_drhe.m) and
%  this folder's independent implementation of Kiem Section 3.5.3
%  (kr_drhe_encode + kr_bits_s4) on the same FX16 frame, and checks that they
%  produce identical residuals and identical bit counts. The replication does
%  not depend on this script.
%  Output: results/crosscheck_matlabsim.txt

clear;
here = fileparts(mfilename('fullpath')); addpath(here);
simDir = fullfile(here, '..', 'Matlab_Sim');
outDir = fullfile(here, 'results'); if ~exist(outDir, 'dir'), mkdir(outDir); end
fid = fopen(fullfile(outDir, 'crosscheck_matlabsim.txt'), 'w');
out = @(varargin) cellfun(@(f) fprintf(f, varargin{:}), {1, fid}, 'UniformOutput', false);
if ~exist(fullfile(simDir, 'compress_drhe.m'), 'file')
    out('Matlab_Sim/compress_drhe.m not found next to this folder; nothing to check.\n');
    fclose(fid); return;
end
cfg = kr_config('sim');
out('Matlab_Sim compress_drhe vs kr_drhe_encode (Kiem 3.5.3), Kiem Table 3.2 scene\n');
for nf = [-75 -87.9]
    sigma = kr_calibrate_noise(cfg, nf);
    adc = kr_generate_adc(cfg, sigma);
    [re, im] = kr_fx16(kr_preprocess_fft(adc, cfg), cfg);
    % this folder
    [dre, dim] = kr_drhe_encode(re, im, cfg, 1);
    bits = kr_bits_s4(dre, cfg.huffLenFixed) + kr_bits_s4(dim, cfg.huffLenFixed);
    % the thesis's MATLAB DRHE (added to the path only here, removed after)
    addpath(simDir);
    fx.real_part = int16(re); fx.imag_part = int16(im); fx.scaleFactor = 1;
    c.numRamps = size(re, 2); c.numRxChannels = size(re, 3);
    C = compress_drhe(fx, c);
    rmpath(simDir);
    sameRes = isequal(double(C.diffReal), dre) && isequal(double(C.diffImag), dim);
    out('NF %6.1f dBFS: residuals identical = %d, bits %d vs %d (diff %d), CR %.4f vs %.4f\n', ...
        nf, sameRes, round(C.totalBits), round(bits), round(C.totalBits - bits), C.CR, numel(re) * 32 / bits);
end
fclose(fid);
