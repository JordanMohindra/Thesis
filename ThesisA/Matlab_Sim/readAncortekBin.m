function s = readAncortekBin(filename_p)
% READANCORTEKBIN Read an Ancortek exported .bin (or .mat) capture into a struct.
%   Mirrors the read_radar_bin helper inside read_radar_data_fmcw.m so the
%   Matlab_Sim adapter can consume the same recordings.
%
%   Output struct fields:
%     .nRx .nTx .fStart(Hz) .fStop(Hz) .sTime(s) .nSamp .ADCsamples(raw)

    if numel(filename_p) >= 4 && strcmpi(filename_p(end-3:end), '.bin')
        fileID = fopen(filename_p);
        if fileID < 0
            error('readAncortekBin:open', 'Could not open file: %s', filename_p);
        end
        data = fread(fileID, inf, 'ushort');
        fclose(fileID);
        s.nRx        = data(1);
        s.nTx        = data(2);
        s.fStart     = data(3) * 1e6;
        s.fStop      = data(4) * 1e6;
        s.sTime      = data(5) * 1e-6;
        s.nSamp      = data(6);
        s.ADCsamples = data(7:end);
    elseif numel(filename_p) >= 4 && strcmpi(filename_p(end-3:end), '.mat')
        r = load(filename_p);
        s.nRx        = r.nRx;
        s.nTx        = r.nTx;
        s.fStart     = r.fStart;
        s.fStop      = r.fStop;
        s.sTime      = r.sTime * 1e-3;
        s.nSamp      = r.nSamp;
        s.ADCsamples = r.ADCsamples;
    else
        error('readAncortekBin:type', 'Unsupported file type: %s', filename_p);
    end
end
