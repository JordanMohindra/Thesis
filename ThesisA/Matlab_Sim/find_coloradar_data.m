function [dataDir, frameFiles] = find_coloradar_data(dataDir)
% FIND_COLORADAR_DATA Locate the ColoRadar cascade frame_*.bin files.
%   [dataDir, frameFiles] = find_coloradar_data()        searches the usual places
%   [dataDir, frameFiles] = find_coloradar_data(dataDir)  checks the given folder
%   The environment variable COLORADAR_DATA, if set, is tried first.
%   frameFiles is sorted by frame number (frame_0, frame_1, ...).
    here = fileparts(mfilename('fullpath'));
    if nargin >= 1 && ~isempty(dataDir)
        candidates = {dataDir};
    else
        candidates = { getenv('COLORADAR_DATA'), ...
            'D:\Jordan''s Thesis\cascade\adc_samples\data', ...
            fullfile(here, '..', '..', '..', 'Jordan''s Thesis', 'cascade', 'adc_samples', 'data'), ...
            fullfile(here, '..', '..', 'Jordan''s Thesis', 'cascade', 'adc_samples', 'data'), ...
            'C:\Users\mohin\Downloads\12_21_2020_ec_hallways_run4\12_21_2020_ec_hallways_run4\cascade\adc_samples\data'};
    end
    for i = 1:numel(candidates)
        d = candidates{i};
        if isempty(d) || ~exist(d, 'dir'), continue; end
        files = dir(fullfile(d, 'frame_*.bin'));
        if isempty(files), continue; end
        num = cellfun(@(s) sscanf(s, 'frame_%d.bin'), {files.name});
        [~, order] = sort(num);
        dataDir = d;
        frameFiles = files(order);
        return
    end
    error('find_coloradar_data: no frame_*.bin files found. Set COLORADAR_DATA to the cascade\\adc_samples\\data folder.');
end
