function grab_impl(wd, name)
%GRAB_IMPL copy the post-implementation reports of one HLS work dir into the transfer folder
X = fullfile('C:\Users\Jordan Mohindra\OneDrive\Documents\Fifth_Year\_xfer\impl', name);
if ~isfolder(X), mkdir(X); end
src = fullfile(wd,'hls','impl','verilog','report');
d = dir(fullfile(src,'*.rpt'));
for k = 1:numel(d)
    if d(k).bytes > 0, copyfile(fullfile(src,d(k).name), fullfile(X,d(k).name)); end
end
e = dir(fullfile(wd,'hls','impl','report','verilog','*_export.rpt'));
for k = 1:numel(e), copyfile(fullfile(e(k).folder,e(k).name), fullfile(X,e(k).name)); end
s = dir(fullfile(wd,'hls','syn','report','*csynth.rpt'));
for k = 1:numel(s), copyfile(fullfile(s(k).folder,s(k).name), fullfile(X,['hls_' s(k).name])); end
fprintf('%s: %d impl reports, %d csynth reports -> %s\n', name, numel(d), numel(s), X);
end
