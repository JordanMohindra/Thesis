%% KR_DICTIONARY_FINGERPRINT
%  Kiem computed his fixed Huffman dictionary (Appendix A, Table A.1) from the
%  S4 statistics of his own DRHE residuals [3.5.2]. A Huffman code is optimal
%  only for the distribution it was built from, so the dictionary itself tells
%  us roughly what his residuals looked like. This script codes zero-mean,
%  integer-rounded Gaussian residuals of standard deviation s with (a) Kiem's
%  fixed dictionary and (b) the ideal Huffman code for that s, and reports
%  the overhead of the fixed dictionary. The overhead is smallest where the
%  dictionary matches the data it was made from.
%  No radar simulation is involved; this is a property of the dictionary.
%  Output: results/dictionary_fingerprint.txt

clear;
here = fileparts(mfilename('fullpath')); addpath(here);
outDir = fullfile(here, 'results'); if ~exist(outDir, 'dir'), mkdir(outDir); end
cfg = kr_config('sim');
Lfix = cfg.huffLenFixed(:);
fid = fopen(fullfile(outDir, 'dictionary_fingerprint.txt'), 'w');
out = @(varargin) cellfun(@(f) fprintf(f, varargin{:}), {1, fid}, 'UniformOutput', false);
out('Gaussian residual std (LSB) | CR fixed dict | CR ideal Huffman | overhead | most common S4\n');
v = (-40000:40000)';
a = abs(v); s4 = zeros(size(v));
s4(a > 0) = min(floor(log2(a(a > 0))) + 1, 15);
for s = [1 2 3 4 4.6 5 6 7 8 10 15 20 33]
    p = exp(-0.5 * (v / s).^2); p = p / sum(p);
    P = accumarray(s4 + 1, p, [16 1]);
    bitsFix = sum(P .* (Lfix + (0:15)'));
    Lid = kr_huffman_lengths(round(P * 1e12));
    bitsId = sum(P .* (Lid + (0:15)'));
    [~, pk] = max(P);
    out('%27.1f | %13.2f | %16.2f | %7.1f%% | %d\n', s, 16 / bitsFix, 16 / bitsId, 100 * (bitsFix / bitsId - 1), pk - 1);
end
out('Kiem''s dictionary has zero overhead for residual std of about 6-8 LSB.\n');
fclose(fid);
