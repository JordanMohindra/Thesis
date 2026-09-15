%% AUDIT: decompose the compression ratio into its two sources.
%
%   source 1 - the FX16 container is under-filled. compress_fx16 fixes its
%              scale factor from the theoretical full-scale ADC sinusoid, but
%              the ColoRadar capture sits far below that, so the top bits of
%              every int16 code are structurally zero. An entropy coder removes
%              those whether or not any prediction happens.
%   source 2 - genuine slow-time (Doppler) redundancy, which is what the
%              predictor is actually for.
%
% Coding the raw FX16 codes with the SAME S4 + Huffman coder but NO prediction
% isolates source 1. The ratio between that and the predicted result is the
% prediction gain, i.e. source 2.
%
% Also reports the order-0 empirical entropy of the residuals, to show how well
% Kiem's fixed Huffman dictionary matches this dataset.

clear; clc;
dataDir = 'D:\Jordan''s Thesis\cascade\adc_samples\data';
opts = struct('txSelect',1:12,'removeDC',true,'fx16EffectiveBits',16);
hl = [4,3,2,2,2,5,6,7,8,9,10,11,14,14,13,12];
NF = 5; NRX = 4;

bpv_raw=[]; bpv_drhe=[]; bpv_lpc=[]; H_raw=[]; H_drhe=[]; pk=[];
s4hist = zeros(1,16); nStable=0; nTotal=0;

for f = 0:NF-1
    bf = fullfile(dataDir, sprintf('frame_%d.bin', f));
    evalc('[cube, config, ~] = loadColoRadarFrame(bf, opts);');
    fx = compress_fx16(rangeFFT(preprocessing(cube, config), config), config);
    R = double(fx.real_part(:,:,1:NRX));  I = double(fx.imag_part(:,:,1:NRX));
    [nB,nR,nC] = size(R);
    nVal = nB*nR*nC*2;
    pk(end+1) = max(max(abs(R(:))),max(abs(I(:))));                      %#ok<SAGROW>

    % ---- no prediction: code the FX16 codes directly ----
    allv = [R(:); I(:)];
    bpv_raw(end+1) = sum(hb(allv,hl))/nVal;                              %#ok<SAGROW>
    H_raw(end+1)   = order0_entropy(allv);                               %#ok<SAGROW>

    % ---- DRHE prediction (vectorised across range bins) ----
    dR = zeros(nB,nR,nC); dI = zeros(nB,nR,nC);
    a=0.6; b=0.4;
    for c = 1:nC
        pmp=zeros(nB,1); pm=zeros(nB,1); ppp=zeros(nB,1); pp=zeros(nB,1); pp2=zeros(nB,1);
        for m = 1:nR
            re=R(:,m,c); im=I(:,m,c);
            cm=sqrt(re.^2+im.^2); cp=atan2(im,re);
            mp=a*pmp+(1-a)*pm;
            php=b*ppp+(2-b)*pp-pp2;
            php(php>pi)=php(php>pi)-2*pi; php(php<-pi)=php(php<-pi)+2*pi;
            dR(:,m,c)=wrap16(re-round(mp.*cos(php)));
            dI(:,m,c)=wrap16(im-round(mp.*sin(php)));
            pp2=pp; pp=cp; ppp=php; pm=cm; pmp=mp;
        end
    end
    dAll = [dR(:); dI(:)];
    bpv_drhe(end+1) = sum(hb(dAll,hl))/nVal;                             %#ok<SAGROW>
    H_drhe(end+1)   = order0_entropy(dAll);                              %#ok<SAGROW>
    s4hist = s4hist + histcounts(s4of(dAll), -0.5:1:15.5);

    % ---- LPC prediction (vectorised; open-loop so predictor uses originals) ----
    bl = 0;
    for c = 1:nC
        for part = 1:2
            if part==1, X = squeeze(R(:,:,c)); else, X = squeeze(I(:,:,c)); end  % nB x nR
            N = nR;
            R0 = sum(X.^2,2);
            R1 = sum(X(:,1:N-1).*X(:,2:N),2);
            R2 = sum(X(:,1:N-2).*X(:,3:N),2);
            dt = R0.^2 - R1.^2;
            a1 = zeros(nB,1); a2 = zeros(nB,1);
            ok = dt ~= 0;
            a1(ok) = (R1(ok).*(R0(ok)-R2(ok)))./dt(ok);
            a2(ok) = (R0(ok).*R2(ok)-R1(ok).^2)./dt(ok);
            bad = ~ok | (abs(a2)>=1) | (abs(a1)>=(1-a2));
            a1(bad)=0; a2(bad)=0;
            nStable = nStable + sum(~bad); nTotal = nTotal + nB;
            Xm1 = [zeros(nB,1) X(:,1:N-1)];
            Xm2 = [zeros(nB,2) X(:,1:N-2)];
            D = wrap16(X - round(a1.*Xm1 + a2.*Xm2));
            bl = bl + sum(hb(D(:),hl));
        end
    end
    ovPerVal = (nB*nC*4*16)/nVal;   % a1,a2 per (bin,rx,I/Q) as 16-bit each
    bpv_lpc(end+1) = bl/nVal + ovPerVal;                                 %#ok<SAGROW>
    fprintf('  frame %d done\n', f);
end

fprintf('\n=================================================================\n');
fprintf('  DECOMPOSITION OF THE COMPRESSION RATIO (%d frames, %d RX)\n', NF, NRX);
fprintf('=================================================================\n');
fprintf('  peak |FX16 code|                    : %d  -> %.1f of 16 bits used\n', max(pk), log2(max(pk))+1);
fprintf('  structurally unused headroom        : %.1f bits\n\n', 16-(log2(max(pk))+1));
fprintf('  bits/value, no prediction (S4+Huff) : %6.3f   -> CR %.3f\n', mean(bpv_raw),  16/mean(bpv_raw));
fprintf('  bits/value, DRHE prediction         : %6.3f   -> CR %.3f\n', mean(bpv_drhe), 16/mean(bpv_drhe));
fprintf('  bits/value, LPC prediction (+ovhd)  : %6.3f   -> CR %.3f\n\n', mean(bpv_lpc), 16/mean(bpv_lpc));
fprintf('  CR from container/entropy alone     : %.3f x\n', 16/mean(bpv_raw));
fprintf('  extra gain from DRHE prediction     : %.3f x\n', mean(bpv_raw)/mean(bpv_drhe));
fprintf('  extra gain from LPC prediction      : %.3f x\n\n', mean(bpv_raw)/mean(bpv_lpc));
fprintf('  LPC coefficient sets passing stability: %.2f%%\n\n', 100*nStable/nTotal);
fprintf('  order-0 entropy of raw codes        : %6.3f bits\n', mean(H_raw));
fprintf('  order-0 entropy of DRHE residuals   : %6.3f bits\n', mean(H_drhe));
fprintf('  Huffman overhead vs entropy (DRHE)  : %+.3f bits/value (%.1f%%)\n', ...
        mean(bpv_drhe)-mean(H_drhe), 100*(mean(bpv_drhe)-mean(H_drhe))/mean(H_drhe));
fprintf('\n  DRHE residual S4 histogram (%% of values):\n');
tot = sum(s4hist);
for i=0:15
    if s4hist(i+1) > 0
        fprintf('    S4=%2d  %6.2f%%   cost %2d bits\n', i, 100*s4hist(i+1)/tot, hl(i+1)+i);
    end
end
fprintf('=================================================================\n');


function w = wrap16(v), w = mod(v+32768,65536)-32768; end
function s = s4of(v)
    av=abs(v); s=zeros(size(v)); nz=av>0; s(nz)=min(15,floor(log2(av(nz)))+1);
end
function b = hb(v, hl)
    s4 = s4of(v); b = zeros(size(v));
    for i=0:15, mk=(s4==i); b(mk)=hl(i+1)+i; end
end
function H = order0_entropy(v)
    u = unique(v); c = histcounts(v,[u(:)' inf]); p = c/sum(c); p=p(p>0);
    H = -sum(p.*log2(p));
end
