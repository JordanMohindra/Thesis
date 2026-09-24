function kr_figures(res, cfg, outDir)
%KR_FIGURES  Figures in the style of Kiem's Figures 3.5, 3.7(c) and 3.13.
P = kr_fullscale_ref(cfg);
X = res.Xref;
f = figure('Visible', 'off', 'Position', [100 100 900 320]);
pk = (2^(cfg.bitWidth-1) - 1) * 2^cfg.shiftBits * sum(kr_hanning(cfg.numSamples)) / (2*cfg.numSamples);
A = 20*log10(abs(X(:, 1, 1)) / pk + realmin);   % 0 dBFS = full-scale sinusoid
plot(0:size(X,1)-1, A); grid on; xlabel('range bin'); ylabel('dBFS');
title('Range FFT output, ramp 1, RX 1 (cf. Kiem Fig. 3.5)');
print(f, fullfile(outDir, 'fig_rangefft.png'), '-dpng', '-r120'); close(f);

f = figure('Visible', 'off', 'Position', [100 100 700 520]);
imagesc(0:cfg.numRamps-1, 0:size(X,1)-1, 10*log10(res.rdRef / P + realmin));
axis xy; colorbar; xlabel('Doppler bin'); ylabel('range bin');
hold on; [r, c] = find(res.detRef); plot(c-1, r-1, 'wo', 'MarkerSize', 6);
title('Range-Doppler map after NCI, dBFS, with detections (cf. Kiem Fig. 3.7c)');
print(f, fullfile(outDir, 'fig_rdmap.png'), '-dpng', '-r120'); close(f);

f = figure('Visible', 'off', 'Position', [100 100 700 360]);
s4 = kr_s4(res.drheRes(:));
histogram(s4, -0.5:1:15.5, 'Normalization', 'probability'); grid on;
xlabel('S4 value'); ylabel('fraction of values');
title('S4 symbols of the DRHE differences, real part (cf. Kiem Fig. 3.13)');
print(f, fullfile(outDir, 'fig_s4hist.png'), '-dpng', '-r120'); close(f);
end
