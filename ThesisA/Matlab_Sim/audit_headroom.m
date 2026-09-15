%% AUDIT: how much of the reported compression ratio is Doppler redundancy,
%% and how much is simply unused int16 dynamic range?
%
% compress_fx16 fixes its scale factor from the *theoretical* maximum range-FFT
% output of a full-scale ADC sinusoid. The ColoRadar capture is far below full
% scale, so the int16 codes occupy only a small part of their range. Any
% entropy coder then wins bits that have nothing to do with slow-time
% correlation. This script separates the two effects by re-quantising the same
% range-FFT data so that it fills int16, and re-running both codecs.

clear; clc;
dataDir = 'D:\Jordan''s Thesis\cascade\adc_samples\data';
opts = struct('txSelect',1:12,'removeDC',true,'fx16EffectiveBits',16);
hl = [4,3,2,2,2,5,6,7,8,9,10,11,14,14,13,12];
NF = 5; NRX = 4;

fprintf('=================================================================\n');
fprintf('  AUDIT: dynamic-range headroom vs genuine redundancy\n');
fprintf('=================================================================\n');

rawPk=0; fxPk=0;
crD_as=[]; crD_fs=[]; crL_as=[]; crL_fs=[]; ebits=[];

for f = 0:NF-1
    bf = fullfile(dataDir, sprintf('frame_%d.bin', f));
    evalc('[cube, config, ~] = loadColoRadarFrame(bf, opts);');
    rawPk = max(rawPk, max(abs([real(cube(:)); imag(cube(:))])));

    rangeFFTData = rangeFFT(preprocessing(cube, config), config);
    fx = compress_fx16(rangeFFTData, config);

    R = double(fx.real_part(:,:,1:NRX));
    I = double(fx.imag_part(:,:,1:NRX));
    pk = max(max(abs(R(:))), max(abs(I(:))));
    fxPk = max(fxPk, pk);
    ebits(end+1) = log2(pk)+1;                       %#ok<SAGROW>

    % --- as-shipped ---
    [bD, bL, ov, inB] = codec_bits(R, I, hl);
    crD_as(end+1) = inB/bD;                          %#ok<SAGROW>
    crL_as(end+1) = inB/(bL+ov);                     %#ok<SAGROW>

    % --- rescaled so the data fills int16 ---
    K = 32767 / pk;
    Rf = double(int16(round(R*K)));
    If = double(int16(round(I*K)));
    [bD2, bL2, ov2, inB2] = codec_bits(Rf, If, hl);
    crD_fs(end+1) = inB2/bD2;                        %#ok<SAGROW>
    crL_fs(end+1) = inB2/(bL2+ov2);                  %#ok<SAGROW>

    fprintf('  frame %d: peak|fx16|=%5d (%.1f bits used of 16)  DRHE %.3f -> %.3f   LPC %.3f -> %.3f\n', ...
        f, pk, log2(pk)+1, crD_as(end), crD_fs(end), crL_as(end), crL_fs(end));
end

fprintf('\n-----------------------------------------------------------------\n');
fprintf('  raw ADC peak |sample|          : %d  (int16 container holds 32767)\n', rawPk);
fprintf('  peak |FX16 code|               : %d  -> %.1f of 16 bits actually used\n', fxPk, log2(fxPk)+1);
fprintf('  unused headroom                : %.1f bits\n', 16-(log2(fxPk)+1));
fprintf('\n  mean CR as-shipped   : DRHE %.4f   LPC %.4f\n', mean(crD_as), mean(crL_as));
fprintf('  mean CR full-scale   : DRHE %.4f   LPC %.4f\n', mean(crD_fs), mean(crL_fs));
fprintf('  CR attributable to headroom: DRHE %.2fx   LPC %.2fx\n', ...
    mean(crD_as)/mean(crD_fs), mean(crL_as)/mean(crL_fs));
fprintf('=================================================================\n');


function [bitsD, bitsL, ov, inB] = codec_bits(R, I, hl)
    [nB, nR, nC] = size(R);
    inB = nB*nR*nC*2*16;
    ov  = nB*nC*4*16;
    bitsD = 0; bitsL = 0;
    a = 0.6; b = 0.4;
    for c = 1:nC
        % ---- DRHE: polar IIR prediction over ramps ----
        pmp = zeros(nB,1); pm = zeros(nB,1);
        ppp = zeros(nB,1); pp = zeros(nB,1); ppp2 = zeros(nB,1);
        for m = 1:nR
            re = R(:,m,c); im = I(:,m,c);
            cm = sqrt(re.^2+im.^2); cp = atan2(im,re);
            mp = a*pmp + (1-a)*pm;
            php = b*ppp + (2-b)*pp - ppp2;
            php(php>pi) = php(php>pi)-2*pi; php(php<-pi) = php(php<-pi)+2*pi;
            dr = wrap16(re - round(mp.*cos(php)));
            di = wrap16(im - round(mp.*sin(php)));
            bitsD = bitsD + sum(hb(dr,hl)) + sum(hb(di,hl));
            ppp2 = pp; pp = cp; ppp = php; pm = cm; pmp = mp;
        end
        % ---- LPC: 2nd-order Yule-Walker per range bin ----
        for n = 1:nB
            for part = 1:2
                if part==1, sq = squeeze(R(n,:,c)); else, sq = squeeze(I(n,:,c)); end
                N = numel(sq);
                R0 = sum(sq.^2); R1 = sum(sq(1:N-1).*sq(2:N)); R2 = sum(sq(1:N-2).*sq(3:N));
                dt = R0^2-R1^2;
                if dt==0, a1=0; a2=0;
                else
                    a1 = (R1*(R0-R2))/dt; a2 = (R0*R2-R1^2)/dt;
                    if abs(a2)>=1 || abs(a1)>=(1-a2), a1=0; a2=0; end
                end
                p1=0; p2=0;
                for m=1:N
                    d = wrap16(sq(m)-round(a1*p1+a2*p2));
                    bitsL = bitsL + hb(d,hl);
                    p2=p1; p1=sq(m);
                end
            end
        end
    end
end

function w = wrap16(v), w = mod(v+32768,65536)-32768; end

function b = hb(v, hl)
    av = abs(v); s4 = zeros(size(v));
    nz = av>0; s4(nz) = min(15, floor(log2(av(nz)))+1);
    b = zeros(size(v));
    for i=0:15, mk = (s4==i); b(mk) = hl(i+1)+i; end
end
