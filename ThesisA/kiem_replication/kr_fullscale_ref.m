function P = kr_fullscale_ref(cfg)
%KR_FULLSCALE_REF  0 dBFS reference power for NF and SNR.
%   'sinusoid': NCI power of a full-scale sinusoid (largest ADC code) that
%               sits exactly on a range bin and a Doppler bin, after the whole
%               chain (range FFT, Doppler FFT, NCI over numRx).
%   'unit'    : power 1 in units where the 32-bit full-scale value is 1.
switch cfg.dbfsMode
    case 'sinusoid'
        A  = (2^(cfg.bitWidth-1) - 1) * 2^cfg.shiftBits;
        pk = A * sum(kr_hanning(cfg.numSamples)) / (2*cfg.numSamples) ...
               * sum(kr_hanning(cfg.numRamps)) / cfg.numRamps;
        P  = cfg.numRx * pk^2;
    case 'unit'
        P  = (2^31)^2;
    otherwise
        error('unknown dbfsMode');
end
end
