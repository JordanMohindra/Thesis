function R = fe_detection_check(frames, tag)
%FE_DETECTION_CHECK  Detection loss of the FX16 quantisation, MATLAB vs on-chip FFT.
%   For each frame: the double-precision chain (reference), the MATLAB FX16
%   codes (compress_fx16) and the FX16 codes the board's radar_fe produced
%   (results/<tag>/fx16_frames.bin) all go through the same Doppler FFT, NCI
%   and peak detector (secondStageProcessing), 4 RX as on the FPGA.
%   Returns per-frame counts; run fe_detection_summary on the saved file.
%
%   R = fe_detection_check(0:9, 'lpc_fe_full')

    if nargin < 2, tag = 'lpc_fe_full'; end
    here = fileparts(mfilename('fullpath'));
    addpath(fullfile(here, '..', 'Matlab_Sim'));
    fxFile = fullfile(here, '..', 'fpga_kcu116', 'results', tag, 'fx16_frames.bin');
    NRX = 4; NB = 128; NR = 192;
    perFrame = 2 * NRX * NB * NR;

    [dataDir, ~] = find_coloradar_data('');
    opts = struct('txSelect', 1:12, 'removeDC', true, 'fx16EffectiveBits', 16, ...
                  'rangeMaxPlot', 25, 'velMaxPlot', []);
    fid = fopen(fxFile, 'r');
    R = [];
    for f = frames
        binFile = fullfile(dataDir, sprintf('frame_%d.bin', f));
        [~, cube, config] = evalc('loadColoRadarFrame(binFile, opts)');
        cube = cube(:, :, 1:NRX);
        config.numRxChannels = NRX;
        fsr = computeFullScaleRefPower(config);

        X = rangeFFT(preprocessing(cube, config), config);            % reference (double)
        [dRef, rdRef] = secondStageProcessing(X, config);

        c = compress_fx16(X, config);                                   % MATLAB FX16
        sf = c.scaleFactor;
        mat = double(c.real_part) + 1j * double(c.imag_part);

        fseek(fid, f * perFrame * 2, 'bof');                            % board FX16
        b = double(fread(fid, perFrame, 'int16=>int16'));
        b = reshape(b, [2, NRX, NB, NR]);
        brd = permute(squeeze(b(1, :, :, :) + 1j * b(2, :, :, :)), [2 3 1]);   % [bin ramp rx]

        d = [real(brd(:) - mat(:)); imag(brd(:) - mat(:))];
        e.mat = [real(mat(:)) - real(X(:)) * sf; imag(mat(:)) - imag(X(:)) * sf];
        e.brd = [real(brd(:)) - real(X(:)) * sf; imag(brd(:)) - imag(X(:)) * sf];

        names = {'mat', 'brd'}; codes = {mat, brd};
        r.frame = f; r.ref = sum(dRef(:));
        r.ndiff = nnz(d); r.maxdiff = max(abs(d));
        m0 = evaluateMetrics(dRef, dRef, rdRef, rdRef, 1, fsr);
        r.nf.ref = m0.NF_dBFS; r.snr.ref = m0.SNR_dB;
        r.sigma = std(real(X(:)) * sf);                                 % data spread in LSB
        for k = 1:2
            [dT, rdT] = secondStageProcessing(codes{k} / sf, config);
            m = evaluateMetrics(dRef, dT, rdRef, rdT, 1, fsr);
            [fpk, fnk] = comparator(dRef, dT);
            r.fn.(names{k}) = fnk; r.fp.(names{k}) = fpk; r.test.(names{k}) = sum(dT(:));
            r.nf.(names{k}) = m.NF_dBFS; r.snr.(names{k}) = m.SNR_dB;
            r.errrms.(names{k}) = sqrt(mean(e.(names{k}).^2));
            r.detsame = [];
        end
        [dB, ~] = secondStageProcessing(brd / sf, config);
        [dM, ~] = secondStageProcessing(mat / sf, config);
        r.detsame = isequal(dB, dM);
        if isempty(R), R = r; else, R(end + 1) = r; end %#ok<AGROW>
    end
    fclose(fid);
end
