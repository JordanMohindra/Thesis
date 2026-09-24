%% KR_LPC_RAW_METHOD_CHECK
%  Does the way the LPC coefficients are estimated change the LPC-Huffman [25]
%  result? kr_lpc_raw uses the autocorrelation method (Levinson-Durbin), which
%  is biased for pure sinusoids over a finite chirp. This script compares it
%  with the covariance method (true least squares over the chirp) on the first
%  64 chirps of receiver 1, at three noise floors. The Huffman dictionary is
%  excluded from both, so only the predictor differs.
%  Output: results/lpc_raw_method_check.txt

clear;
here = fileparts(mfilename('fullpath')); addpath(here);
outDir = fullfile(here, 'results'); if ~exist(outDir, 'dir'), mkdir(outDir); end
cfg = kr_config('sim');
fid = fopen(fullfile(outDir, 'lpc_raw_method_check.txt'), 'w');
out = @(varargin) cellfun(@(f) fprintf(f, varargin{:}), {1, fid}, 'UniformOutput', false);
out('LPC-Huffman on raw ADC: autocorrelation vs covariance coefficients (64 chirps, RX1)\n');
for nf = [-140 -87.9 -75]
    sig = kr_calibrate_noise(cfg, nf);
    adc = kr_generate_adc(cfg, sig);
    x = double(adc(:, 1:64, 1));
    for p = [8 10]
        o = kr_lpc_raw(adc(:, 1:64, 1), p);
        [N, C] = size(x); e = zeros(N - p, C);
        for c = 1:C
            A = zeros(N - p, p);
            for j = 1:p, A(:, j) = x(p+1-j:N-j, c); end
            a = double(single(A \ x(p+1:N, c)));
            e(:, c) = x(p+1:N, c) - round(A * a);
        end
        lo = min(e(:)); cnt = accumarray(e(:) - lo + 1, 1);
        L = kr_huffman_lengths(cnt);
        bits = sum(cnt .* L) + p * 32 * C + 16 * p * C;   % residual + coefficients + p warm-up samples
        out('NF %6.1f dBFS  ADC noise %6.1f codes  p=%2d | autocorrelation CR %.2f (residual std %6.1f) | covariance CR %.2f (residual std %6.1f)\n', ...
            nf, sig, p, o.CRnoDict, o.residualStd, N*C*16/bits, std(e(:)));
    end
end
fclose(fid);
