function [chans, labels] = getAncortekChannels(ADCsamples, handles)
% GETANCORTEKCHANNELS Recover every valid Tx/Rx complex stream from a capture.
%   Strips the per-sweep USB/header tags and demuxes the interleaved I/Q into
%   per-Tx/Rx complex vectors (each = all sweeps concatenated). Identical logic
%   to read_radar_data_fmcw.m's local get_all_channels/get_complex_data_from_sdr
%   so offline processing matches the live SDRadar.m demux exactly.
%
%   Input:
%     ADCsamples - raw sample vector (from readAncortekBin)
%     handles    - struct with .NTS (samples/sweep), .Num_Rx, .Num_Tx
%
%   Output:
%     chans  - 1xK cell of complex column vectors (only the non-empty channels)
%     labels - 1xK cell of channel names, e.g. {'T1R1','T1R2',...}

    [T1R1,T1R2,T1R3,T1R4,T2R1,T2R2,T2R3,T2R4] = ...
        getComplexDataFromSdr(ADCsamples, handles);
    allCh  = {T1R1,T1R2,T1R3,T1R4,T2R1,T2R2,T2R3,T2R4};
    allLbl = {'T1R1','T1R2','T1R3','T1R4','T2R1','T2R2','T2R3','T2R4'};
    chans = {}; labels = {};
    for i = 1:numel(allCh)
        if ~isempty(allCh{i})
            chans{end+1}  = allCh{i};   %#ok<AGROW>
            labels{end+1} = allLbl{i};  %#ok<AGROW>
        end
    end
end

%% ======================================================================== %%
function [T1R1, T1R2, T1R3, T1R4, T2R1, T2R2, T2R3, T2R4] = ...
    getComplexDataFromSdr(ADCsamples, handles)
% Strip per-sweep headers and demux interleaved I/Q into per-Tx/Rx streams.

    % Discard 2048 leftover USB-buffer samples
    ADCsamples = double(ADCsamples(2049:end));

    % Tx1 sweep headers are tagged >= 49152
    ind_Tx1 = find(ADCsamples >= 49152);
    ind_Tx1_diff = diff(ind_Tx1);
    if any(ind_Tx1_diff ~= handles.NTS*handles.Num_Rx*2*2) || isempty(ind_Tx1)
        fprintf('Warning: possible data loss in Tx1 stream.\n');
    end
    ADCsamples(ind_Tx1) = ADCsamples(ind_Tx1) - 49152;

    if handles.Num_Tx == 2
        % Tx2 sweep headers are tagged 32768..49151
        ind_Tx2 = find(ADCsamples < 49152 & ADCsamples >= 32768);
        ind_Tx2_diff = diff(ind_Tx2);
        if any(ind_Tx2_diff ~= handles.NTS*handles.Num_Rx*2*2) || isempty(ind_Tx2)
            fprintf('Warning: possible data loss in Tx2 stream.\n');
        end
        ADCsamples(ind_Tx2) = ADCsamples(ind_Tx2) - 32768;

        raw   = ADCsamples(ind_Tx1(1):ind_Tx2(end-1)+handles.NTS*2*handles.Num_Rx-1);
        raw_m = reshape(raw, handles.NTS*2*handles.Num_Rx, []);
        nsw   = size(raw_m,2)/2;
        raw_Tx1_m = raw_m(:, 1:2:nsw*2);
        raw_Tx2_m = raw_m(:, 2:2:nsw*2);
    else
        raw   = ADCsamples(ind_Tx1(1):end);
        nfull = floor(numel(raw)/(handles.NTS*2*handles.Num_Rx));
        raw   = raw(1:nfull*handles.NTS*2*handles.Num_Rx);
        raw_Tx1_m = reshape(raw, handles.NTS*2*handles.Num_Rx, []);
        raw_Tx2_m = [];
    end

    [T1R1,T1R2,T1R3,T1R4] = demuxRx(raw_Tx1_m, handles.NTS, handles.Num_Rx);
    if isempty(raw_Tx2_m)
        [T2R1,T2R2,T2R3,T2R4] = deal([],[],[],[]);
    else
        [T2R1,T2R2,T2R3,T2R4] = demuxRx(raw_Tx2_m, handles.NTS, handles.Num_Rx);
    end
end

%% ======================================================================== %%
function [R1,R2,R3,R4] = demuxRx(raw_Tx_m, NTS, nRx)
% Split one Tx matrix (interleaved I/Q per Rx) into complex Rx streams.
    [R1,R2,R3,R4] = deal([],[],[],[]);
    switch nRx
        case 4
            R1 = vecify(raw_Tx_m(1:8:NTS*8,:)   + 1i*raw_Tx_m(2:8:NTS*8+1,:));
            R2 = vecify(raw_Tx_m(3:8:NTS*8+2,:) + 1i*raw_Tx_m(4:8:NTS*8+3,:));
            R3 = vecify(raw_Tx_m(5:8:NTS*8+4,:) + 1i*raw_Tx_m(6:8:NTS*8+5,:));
            R4 = vecify(raw_Tx_m(7:8:NTS*8+6,:) + 1i*raw_Tx_m(8:8:NTS*8+7,:));
        case 2
            R1 = vecify(raw_Tx_m(1:4:NTS*4,:)   + 1i*raw_Tx_m(2:4:NTS*4+1,:));
            R2 = vecify(raw_Tx_m(3:4:NTS*4+2,:) + 1i*raw_Tx_m(4:4:NTS*4+3,:));
        case 1
            R1 = vecify(raw_Tx_m(1:2:NTS*2,:)   + 1i*raw_Tx_m(2:2:NTS*2+1,:));
    end
end

%% ======================================================================== %%
function v = vecify(M)
    v = M(:);
end
