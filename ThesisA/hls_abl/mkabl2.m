%% MKABL2  extra replica variants that test explanations of the LUT gap to Kiem
%  kpk3 : replica (fixed point, open loop, II=1) + Kiem-literal packer (4 inserts, int offset)
%  kpk0 : replica + DRHE-1's original packer (8 inserts, int offset)
root = 'D:\Thesis\ThesisA\hls_abl';
src  = 'C:\Users\Jordan Mohindra\OneDrive\Documents\Fifth_Year\_xfer\abl';
bin  = 'D:\Thesis\ThesisA\hls_component\coloradar_multiframe.bin';
V = { 'kpk3', [3 1 1 1], 'xcku5p-ffvb676-2-e', 5
      'kpk0', [0 1 1 1], 'xcku5p-ffvb676-2-e', 5
      'k23',  [2 1 1 1], 'xcku5p-ffvb676-2-e', 5 };
files = {'drhe_common.h','drhe_abl_common.h','drhe_abl_compress.h','drhe_abl_compress.cpp','drhe_abl_decompress.cpp','drhe_abl_tb.cpp'};
for k = 1:size(V,1)
    d = fullfile(root, V{k,1}); if ~isfolder(d), mkdir(d); end
    for f = files, copyfile(fullfile(src,f{1}), fullfile(d,f{1})); end
    fid = fopen(fullfile(d,'abl_variant.h'),'w');
    fprintf(fid,'#define ABL_PACK %d\n#define ABL_RESET %d\n#define ABL_ARITH %d\n#define ABL_LOOP %d\n', V{k,2});
    fprintf(fid,'#define ABL_MAXFRAMES %d\n', V{k,4});
    if strcmp(V{k,1},'k23'), fprintf(fid,'#define ABL_DEPTH23 1\n'); end
    fclose(fid);
    cfg = sprintf(['part=%s\n\n[hls]\nclock=100MHz\nsyn.file=drhe_abl_compress.cpp\nsyn.top=drhe_abl_compress\n' ...
        'tb.file=drhe_abl_tb.cpp\ntb.file=drhe_abl_decompress.cpp\ntb.file=%s\ncsim.O=true\n\n' ...
        'package.output.format=ip_catalog\npackage.output.syn=false\n' ...
        'vivado.flow=impl\nvivado.clock=10\nvivado.report_level=2\nvivado.max_timing_paths=10\n'], V{k,3}, strrep(bin,'\','/'));
    fid = fopen(fullfile(d,'abl.cfg'),'w'); fwrite(fid,cfg); fclose(fid);
end
fprintf('created %d folders\n', size(V,1));
