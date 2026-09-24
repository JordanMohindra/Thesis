function [re, im, scale] = kr_fx16(X, cfg)
%KR_FX16  FX16 quantisation [3.4.1]: the 16-bit fixed-point range-FFT data
%   that DRHE compresses losslessly. Returns integer-valued doubles in the
%   int16 range and the scale that maps them back to 32-bit units (X ~ re/scale).
switch cfg.fx16Mode
    case 'hw'      % top 16 bits of the 32-bit full-scale value
        scale = 2^-16;
    case 'peak'    % full-scale sinusoid -> 32767
        A = (2^(cfg.bitWidth-1) - 1) * 2^cfg.shiftBits;
        scale = 32767 / (A * sum(kr_hanning(cfg.numSamples)) / (2*cfg.numSamples));
    otherwise
        error('unknown fx16Mode');
end
re = min(max(round(real(X) * scale), -32768), 32767);
im = min(max(round(imag(X) * scale), -32768), 32767);
% integers have no negative zero; without this atan2(-0, x<0) = -pi while the
% decoder, which rebuilds +0, gets +pi, and the predictions part company
re = re + 0; im = im + 0;
end
