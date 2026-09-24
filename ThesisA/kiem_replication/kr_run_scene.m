function res = kr_run_scene(cfg, opts)
%KR_RUN_SCENE  One pass of Kiem's simulation workflow [Figure 3.1] on one
%   generated frame: input data -> preprocessing -> range FFT -> compress ->
%   decompress -> 2nd-stage processing -> comparator -> results.
%   opts.lite = true skips the lossy schemes and the LPC-order sweep, and
%   runs LPC-Huffman at order 10 only (the
%   best order in the full run; 5 real sinusoids need 10 poles). Used by the
%   noise sweep.
if nargin < 2, opts = struct; end
if ~isfield(opts, 'lite'), opts.lite = false; end
if ~isfield(opts, 'noiseNF'), opts.noiseNF = cfg.noiseAfterNCI_dBFS; end
if ~isfield(opts, 'lag'), opts.lag = 1; end
if ~isfield(opts, 'skipRaw'), opts.skipRaw = false; end

% ---- input data, preprocessing, range FFT ---------------------------------
sigma = kr_calibrate_noise(cfg, opts.noiseNF);
[adc, gi] = kr_generate_adc(cfg, sigma);
X = kr_preprocess_fft(adc, cfg);
res.sigmaLSB = sigma; res.clipped = gi.clippedFraction; res.ampScale = gi.ampScale;
res.cfg = cfg; res.opts = opts;

% ---- reference: FP16 [3.4.1]; double precision kept for information -------
rdD = kr_second_stage(X, cfg);          detD = kr_detect(rdD, cfg);
Xh  = kr_fp16(X);
rdR = kr_second_stage(Xh, cfg);         detR = kr_detect(rdR, cfg);
res.nRef = nnz(detR);
res.metrics.FP16 = kr_metrics(detR, detR, rdR, cfg, 1);
res.metrics.Double = kr_metrics(detR, detD, rdD, cfg, 1);

% ---- FX16 ------------------------------------------------------------------
[re, im, sc] = kr_fx16(X, cfg);
Xf  = complex(re, im) / sc;
rdF = kr_second_stage(Xf, cfg);         detF = kr_detect(rdF, cfg);
mFX = kr_metrics(detR, detF, rdF, cfg, 1);
res.metrics.FX16 = mFX;
inBits = numel(re) * 32;
res.fx16.maxAbs   = max(abs([re(:); im(:)]));
res.fx16.zeroFrac = mean([re(:); im(:)] == 0);
res.fx16.noiseStd = std([re(:); im(:)]);
res.fx16.bitsUsed = ceil(log2(res.fx16.maxAbs + 1)) + 1;
% noise-only statistics: range bins at least 8 bins from every target
far = true(size(re, 1), 1);
for b = cfg.targets.rangeBin, far(max(1, b+1-8):min(end, b+1+8)) = false; end
far(1:8) = false;                                   % DC leakage
nre = re(far, :, :); nim = im(far, :, :);
res.fx16.noiseOnlyStd = std([nre(:); nim(:)]);

% lossless methods reconstruct FX16 exactly, so their detection metrics are
% FX16's; each round trip is checked, not assumed.
lossless = @(CR) setfield(mFX, 'CR', CR); %#ok<SFLD>

% ---- no prediction: the same coder on the raw FX16 values ------------------
res.metrics.NoPred = lossless(inBits / (kr_bits_s4(re, cfg.huffLenFixed) + kr_bits_s4(im, cfg.huffLenFixed)));

% ---- DRHE [3.5.3] ------------------------------------------------------------
lag = opts.lag;
[dre, dim] = kr_drhe_encode(re, im, cfg, lag);
[r2, i2] = kr_drhe_decode(dre, dim, cfg, lag);
res.drheLossless = isequal(r2, re) && isequal(i2, im);
bFixed = kr_bits_s4(dre, cfg.huffLenFixed) + kr_bits_s4(dim, cfg.huffLenFixed);
res.metrics.DRHE_fixed = lossless(inBits / bFixed);
res.drheRes = dre;                       % for the S4 histogram figure
bR4S4 = kr_bits_r4s4(dre) + kr_bits_r4s4(dim);
res.metrics.DRHE_RLE = lossless(inBits / bR4S4);
bAd = kr_bits_s4(dre, []) + kr_bits_s4(dim, []);
res.metrics.DRHE_noRLE = lossless(inBits / bAd);
res.metrics.NoPred_RLE = lossless(inBits / (kr_bits_r4s4(re) + kr_bits_r4s4(im)));

% ---- LPC along slow time on range-FFT data (this thesis's LPC) -------------
L = kr_lpc_fft(re, im, cfg, lag);
res.lpcFFTLossless = L.lossless;
res.metrics.LPC_FFT = lossless(inBits / L.bitsFixed);
res.metrics.LPC_FFT_ideal = lossless(inBits / L.bitsAdaptive);

% ---- LPC-Huffman on raw ADC [2.7.4, ref 25] ---------------------------------
if opts.skipRaw, orders = []; elseif opts.lite, orders = 10; else, orders = cfg.lpcRawOrders; end
best = [];
for p = orders
    o = kr_lpc_raw(adc, p);
    res.lpcRaw(p) = o; %#ok<AGROW>
    if isempty(best) || o.CR > best.CR, best = o; end
end
if ~isempty(orders)
    res.lpcRawBest = best;
    res.lpcRawLossless = all([res.lpcRaw(orders).lossless]);
    % raw-ADC coding cannot change the range-FFT data it decodes to: its
    % detections are those of the full-precision FFT of the same ADC codes
    res.metrics.LPC_raw = kr_metrics(detR, detD, rdD, cfg, best.CR);
end

% ---- lossy schemes of Kiem's design space ----------------------------------
if ~opts.lite
    for meth = {'CMPRA', 'CMPRB', 'EGE10', 'EGE8', 'EGE6', 'EGE4'}
        [rq, iq, CR] = kr_lossy(re, im, meth{1});
        rdQ = kr_second_stage(complex(rq, iq) / sc, cfg);
        res.metrics.(meth{1}) = kr_metrics(detR, kr_detect(rdQ, cfg), rdQ, cfg, CR);
    end
end

res.rdRef = rdR; res.detRef = detR; res.Xref = Xh;
end
