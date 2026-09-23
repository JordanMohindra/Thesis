%% MKABL  create one HLS work folder per ablation variant and a runner script
%  Variant = [PACK RESET ARITH LOOP], part suffix
root = 'D:\Thesis\ThesisA\hls_abl';
src  = 'C:\Users\Jordan Mohindra\OneDrive\Documents\Fifth_Year\_xfer\abl';
bin  = 'D:\Thesis\ThesisA\hls_component\coloradar_multiframe.bin';
%     name     variant     part                  csim frames
V = { 'ctrl',   [0 0 0 0], 'xcku5p-ffvb676-2-e', 50
      'p1',     [1 0 0 0], 'xcku5p-ffvb676-2-e', 5
      'p2',     [2 0 0 0], 'xcku5p-ffvb676-2-e', 5
      'p2r',    [2 1 0 0], 'xcku5p-ffvb676-2-e', 5
      'fxc',    [2 1 1 0], 'xcku5p-ffvb676-2-e', 10
      'k',      [2 1 1 1], 'xcku5p-ffvb676-2-e', 10
      'f',      [0 0 1 0], 'xcku5p-ffvb676-2-e', 5
      'k_sg1',  [2 1 1 1], 'xcku5p-ffvb676-1-e', 5 };
if ~isfolder(root), mkdir(root); end
files = {'drhe_common.h','drhe_abl_common.h','drhe_abl_compress.h','drhe_abl_compress.cpp','drhe_abl_decompress.cpp','drhe_abl_tb.cpp'};
for k = 1:size(V,1)
    d = fullfile(root, V{k,1}); if ~isfolder(d), mkdir(d); end
    for f = files, copyfile(fullfile(src,f{1}), fullfile(d,f{1})); end
    v = V{k,2};
    fid = fopen(fullfile(d,'abl_variant.h'),'w');
    fprintf(fid,'#define ABL_PACK %d\n#define ABL_RESET %d\n#define ABL_ARITH %d\n#define ABL_LOOP %d\n', v);
    if V{k,4} < 50, fprintf(fid,'#define ABL_MAXFRAMES %d\n', V{k,4}); end
    fclose(fid);
    cfg = sprintf(['part=%s\n\n[hls]\nclock=100MHz\nsyn.file=drhe_abl_compress.cpp\nsyn.top=drhe_abl_compress\n' ...
        'tb.file=drhe_abl_tb.cpp\ntb.file=drhe_abl_decompress.cpp\ntb.file=%s\ncsim.O=true\n\n' ...
        'package.output.format=ip_catalog\npackage.output.syn=false\n' ...
        'vivado.flow=impl\nvivado.clock=10\nvivado.report_level=2\nvivado.max_timing_paths=10\n'], V{k,3}, strrep(bin,'\','/'));
    fid = fopen(fullfile(d,'abl.cfg'),'w'); fwrite(fid,cfg); fclose(fid);
end
fprintf('created %d variant folders under %s\n', size(V,1), root);
