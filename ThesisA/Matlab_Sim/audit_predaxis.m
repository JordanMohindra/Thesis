%% AUDIT: choose the correct prediction axis for a 12-TX TDM-MIMO cascade.
% The data arrives in TDM time order, ramp = c*Nt + t, so ramp m-1 is a
% DIFFERENT TX antenna 11 times out of 12. Predicting from ramp m-Nt keeps the
% predictor on the same physical TX and therefore on a genuine slow-time axis.
% Cost in hardware: Nt copies of the predictor state.
%
% Variants:
%   0  no prediction (S4+Huffman only)          - the entropy-coder baseline
%   1  DRHE, lag 1   (as implemented)
%   2  DRHE, lag Nt  (per-TX predictor state)
%   3  LPC over the whole 192-ramp axis, lag 1/2 (as implemented)
%   4  LPC per TX block (N=16), lag 1/2, Nt x coefficient overhead
%   5  LPC over the whole axis, lags Nt / 2Nt, one coefficient set per (bin,rx,IQ)

clear; clc;
dataDir = 'D:\Jordan''s Thesis\cascade\adc_samples\data';
hl = [4,3,2,2,2,5,6,7,8,9,10,11,14,14,13,12];
NF = 5; NRX = 4; Nt = 12; Nc = 16;
acc = zeros(1,6); nfr = 0;

for f = 0:NF-1
    bf = fullfile(dataDir, sprintf('frame_%d.bin', f));
    o = struct('txSelect',1:12,'removeDC',true,'fx16EffectiveBits',16);
    evalc('[cube, config, ~] = loadColoRadarFrame(bf, o);');
    fx = compress_fx16(rangeFFT(preprocessing(cube, config), config), config);
    R = double(fx.real_part(:,:,1:NRX)); I = double(fx.imag_part(:,:,1:NRX));
    [nB,nR,nC] = size(R); nVal = nB*nR*nC*2;

    acc(1) = acc(1) + sum(hb([R(:);I(:)],hl))/nVal;
    acc(2) = acc(2) + drhe_bits(R,I,1 ,hl)/nVal;
    acc(3) = acc(3) + drhe_bits(R,I,Nt,hl)/nVal;

    % LPC variant 3: one coeff set per (bin,rx,IQ), lags 1,2 over 192 ramps
    [b3,ns3] = lpc_bits(R,I,1,hl,1);
    acc(4) = acc(4) + b3/nVal + (nB*nC*2*2*16)/nVal;

    % LPC variant 4: one coeff set per (bin,rx,IQ,TX), lags 1,2 within each
    %                16-ramp per-TX block
    b4 = 0;
    for t = 1:Nt
        idx = t:Nt:nR;
        [bb,~] = lpc_bits(R(:,idx,:),I(:,idx,:),1,hl,1);
        b4 = b4 + bb;
    end
    acc(5) = acc(5) + b4/nVal + (nB*nC*2*2*16*Nt)/nVal;

    % LPC variant 5: one coeff set per (bin,rx,IQ), lags Nt, 2Nt
    [b5,~] = lpc_bits(R,I,Nt,hl,Nt);
    acc(6) = acc(6) + b5/nVal + (nB*nC*2*2*16)/nVal;

    nfr = nfr + 1;
    fprintf('  frame %d done\n', f);
end
acc = acc / nfr;

nm = {'0  no prediction (S4+Huffman only)', ...
      '1  DRHE lag 1        (as implemented)', ...
      '2  DRHE lag Nt=12    (per-TX state)', ...
      '3  LPC lag 1,2 over 192 ramps (as impl.)', ...
      '4  LPC lag 1,2 per-TX block N=16', ...
      '5  LPC lag 12,24 over 192 ramps'};
fprintf('\n=================================================================\n');
fprintf('  PREDICTION AXIS STUDY (%d frames, %d RX, 128 bins, 192 ramps)\n', nfr, NRX);
fprintf('=================================================================\n');
for i=1:6
    fprintf('  %-42s %6.3f b/val   CR %5.3f   pred-gain %.3fx\n', ...
        nm{i}, acc(i), 16/acc(i), acc(1)/acc(i));
end
fprintf('=================================================================\n');

% ---------- helpers ----------
function tot = drhe_bits(R,I,lag,hl)
    [nB,nR,nC]=size(R); a=0.6; b=0.4; tot=0;
    for c=1:nC
        for off=1:lag
            idx = off:lag:nR;
            pmp=zeros(nB,1); pm=zeros(nB,1); ppp=zeros(nB,1); pp=zeros(nB,1); pp2=zeros(nB,1);
            for kk=1:numel(idx)
                m=idx(kk); re=R(:,m,c); im=I(:,m,c);
                cm=sqrt(re.^2+im.^2); cp=atan2(im,re);
                mp=a*pmp+(1-a)*pm;
                php=b*ppp+(2-b)*pp-pp2;
                php(php>pi)=php(php>pi)-2*pi; php(php<-pi)=php(php<-pi)+2*pi;
                tot = tot + sum(hb(wrap16(re-round(mp.*cos(php))),hl)) ...
                          + sum(hb(wrap16(im-round(mp.*sin(php))),hl));
                pp2=pp; pp=cp; ppp=php; pm=cm; pmp=mp;
            end
        end
    end
end

function [tot,nStable] = lpc_bits(R,I,L1,hl,Lstep)
    % predictor: x_hat[m] = a1*x[m-L1] + a2*x[m-L1-Lstep]
    [nB,nR,nC]=size(R); tot=0; nStable=0;
    L2 = L1 + Lstep;
    for c=1:nC
        for part=1:2
            if part==1, X=squeeze(R(:,:,c)); else, X=squeeze(I(:,:,c)); end
            if nB==1, X=reshape(X,1,[]); end
            N=nR;
            if N <= L2, tot = tot + sum(hb(X(:),hl)); continue; end
            R0=sum(X.^2,2);
            R1=sum(X(:,1:N-L1).*X(:,1+L1:N),2);
            R2=sum(X(:,1:N-L2).*X(:,1+L2:N),2);
            dt=R0.^2-R1.^2;
            a1=zeros(nB,1); a2=zeros(nB,1); ok=dt~=0;
            a1(ok)=(R1(ok).*(R0(ok)-R2(ok)))./dt(ok);
            a2(ok)=(R0(ok).*R2(ok)-R1(ok).^2)./dt(ok);
            bad=~ok|(abs(a2)>=1)|(abs(a1)>=(1-a2));
            a1(bad)=0; a2(bad)=0; nStable=nStable+sum(~bad);
            Xm1=[zeros(nB,L1) X(:,1:N-L1)];
            Xm2=[zeros(nB,L2) X(:,1:N-L2)];
            D=wrap16(X-round(a1.*Xm1+a2.*Xm2));
            tot = tot + sum(hb(D(:),hl));
        end
    end
end

function w = wrap16(v), w = mod(v+32768,65536)-32768; end
function s = s4of(v)
    av=abs(v); s=zeros(size(v)); nz=av>0; s(nz)=min(15,floor(log2(av(nz)))+1);
end
function b = hb(v, hl)
    s4=s4of(v); b=zeros(size(v));
    for i=0:15, mk=(s4==i); b(mk)=hl(i+1)+i; end
end
