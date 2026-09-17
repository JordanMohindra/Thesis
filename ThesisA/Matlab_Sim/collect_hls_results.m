%% COLLECT_HLS_RESULTS
%  Reads the four FPGA numbers (LUT / FF / BRAM / DSP), the estimated clock
%  period and the co-simulated frame latency straight out of the Vitis report
%  files, for every design, and prints one table.
%
%  Nothing here is typed by hand - if a number changes because a design was
%  re-synthesised, this picks it up.
%
%  WHERE EACH NUMBER COMES FROM
%    LUT / FF / BRAM / DSP   <work_dir>/hls/syn/report/csynth.rpt
%                            top-level row of the "Performance & Resource
%                            Estimates" table, the one beginning "|+ <top>"
%    Estimated clock period  <work_dir>/hls/syn/report/<top>_csynth.xml
%                            <EstimatedClockPeriod>, in ns.  Fmax = 1000/that.
%    Frame latency (cycles)  <work_dir>/hls/sim/report/<top>_cosim.rpt
%                            the "Verilog" row.  Co-simulation only - synthesis
%                            cannot give this.
%
%  TO REGENERATE THE REPORTS
%    synthesis (resources, Fmax, II):
%        v++ -c --mode hls --config <cfg> --work_dir <work_dir>
%    co-simulation (latency)  - must run AFTER synthesis:
%        vitis-run --mode hls --cosim --config <cfg> --work_dir <work_dir>

clear; clc;
BASE = 'D:\Thesis\ThesisA\hls_component';

%  work_dir              top function         label
D = { 'hls_component',  'drhe_compress',      'DRHE-1'
      'hls_tdm',        'drhe_tdm_compress',  'DRHE-n'
      'lpc_component',  'lpc_compress',       'LPC-1,2'
      'hls_lpc_tdm',    'lpc_tdm_compress',   'LPC-n,2n' };

% xcku5p-ffvb676-2-e capacity
CAP = struct('LUT',216960,'FF',433920,'BRAM',960,'DSP',1824);

fprintf('Source: Vitis report files under %s\n\n', BASE);
fprintf('%-10s %9s %8s %7s %6s %10s %9s %10s %6s\n', ...
        'design','LUT','FF','BRAM','DSP','clk(ns)','Fmax(MHz)','latency','II');
fprintf('%s\n', repmat('-',1,84));

for k = 1:size(D,1)
    wd = fullfile(BASE, D{k,1});  top = D{k,2};  lab = D{k,3};
    [lut,ff,bram,dsp,ii] = read_csynth(fullfile(wd,'hls','syn','report','csynth.rpt'), top);
    est = read_clock(fullfile(wd,'hls','syn','report',[top '_csynth.xml']));
    lat = read_cosim(fullfile(wd,'hls','sim','report',[top '_cosim.rpt']));

    fprintf('%-10s %9s %8s %7s %6s %10s %9s %10s %6s\n', lab, ...
        n2s(lut), n2s(ff), n2s(bram), n2s(dsp), ...
        f2s(est,'%.3f'), f2s(1000/est,'%.2f'), n2s(lat), n2s(ii));
end

fprintf('\n%% of device (%d LUT / %d FF / %d BRAM_18K / %d DSP):\n', ...
        CAP.LUT, CAP.FF, CAP.BRAM, CAP.DSP);
fprintf('%-10s %9s %8s %7s %6s\n','design','LUT','FF','BRAM','DSP');
fprintf('%s\n', repmat('-',1,44));
for k = 1:size(D,1)
    wd = fullfile(BASE, D{k,1});  top = D{k,2};
    [lut,ff,bram,dsp] = read_csynth(fullfile(wd,'hls','syn','report','csynth.rpt'), top);
    fprintf('%-10s %8.1f%% %7.1f%% %6.1f%% %5.1f%%\n', D{k,3}, ...
        100*lut/CAP.LUT, 100*ff/CAP.FF, 100*bram/CAP.BRAM, 100*dsp/CAP.DSP);
end
fprintf('\n(A "-" means that report file is not present: a work_dir that was\n');
fprintf(' re-used by a later run loses the earlier design''s cosim report.)\n');
fprintf('\nThroughput @ 100 MHz = 3,145,728 input bits / (latency x 10 ns):\n');
for k = 1:size(D,1)
    lat = read_cosim(fullfile(BASE,D{k,1},'hls','sim','report',[D{k,2} '_cosim.rpt']));
    if ~isnan(lat)
        fprintf('  %-10s %6.3f Gbit/s   (%.1f bits/cycle)\n', D{k,3}, ...
                3145728/(lat*10e-9)/1e9, 3145728/lat);
    end
end

% ---------------------------------------------------------------- helpers
function [lut,ff,bram,dsp,ii] = read_csynth(f, top)
    lut=NaN; ff=NaN; bram=NaN; dsp=NaN; ii=NaN;
    if exist(f,'file')~=2, return; end
    c = strsplit(fileread(f), newline);
    for i = 1:numel(c)
        if contains(c{i}, ['|+ ' top])
            % the four "<number> (<pct>%)" fields, in order: BRAM DSP FF LUT
            tk = regexp(c{i}, '\|\s*(\d+)\s*\(', 'tokens');
            if numel(tk) >= 4
                bram = str2double(tk{1}{1}); dsp = str2double(tk{2}{1});
                ff   = str2double(tk{3}{1}); lut = str2double(tk{4}{1});
            end
        end
        % worst initiation interval across the pipelined loops.
        % Columns of this table are pipe-separated:
        %   2 name | 3 issue | 4 violation | 5 iter-latency | 6 INTERVAL |
        %   7 trip | 8 pipelined | ...
        if contains(c{i},' o ') && contains(c{i},'yes')
            fl = strsplit(c{i}, '|');
            if numel(fl) >= 8 && strcmp(strtrim(fl{8}),'yes')
                v = str2double(strtrim(fl{6}));
                if ~isnan(v) && (isnan(ii) || v > ii), ii = v; end
            end
        end
    end
end

function est = read_clock(f)
    est = NaN;
    if exist(f,'file')~=2, return; end
    m = regexp(fileread(f), '<EstimatedClockPeriod>([\d.]+)</EstimatedClockPeriod>', 'tokens','once');
    if ~isempty(m), est = str2double(m{1}); end
end

function lat = read_cosim(f)
    lat = NaN;
    if exist(f,'file')~=2, return; end
    c = strsplit(fileread(f), newline);
    for i = 1:numel(c)
        if contains(c{i},'Verilog') && contains(c{i},'Pass')
            tk = regexp(c{i}, '\|\s*(\d+)\s*\|', 'tokens');
            if ~isempty(tk), lat = str2double(tk{1}{1}); end
        end
    end
end

function s = n2s(v)
    if isnan(v), s = '-'; else, s = sprintf('%d', v); end
end
function s = f2s(v, fmt)
    if isnan(v) || isinf(v), s = '-'; else, s = sprintf(fmt, v); end
end
