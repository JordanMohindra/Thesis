%% Figure data for the long-form report.
%  Produces, over NF frames and NRX channels:
%    - S4 category histograms for: no prediction, DRHE lag 1, DRHE lag 12,
%      LPC lag 1/2, LPC lag 12/24
%    - residual magnitude quantiles for each
%    - the raw FX16 magnitude distribution
%  Writes a CSV per quantity into _runlogs\ for the report figures.

clear; clc;
dataDir = 'D:\Jordan''s Thesis\cascade\adc_samples\data';
outDir  = 'C:\Users\Jordan Mohindra\OneDrive\Documents\Fifth_Year\Thesis\ThesisA\Matlab_Sim\_runlogs\';
hl = [4,3,2,2,2,5,6,7,8,9,10,11,14,14,13,12];
NF = 5; NRX = 4; Nt = 12;

H = zeros(5,16);          % S4 histograms
MAGQ = zeros(5,9);        % magnitude quantiles
q = [0.5 0.75 0.9 0.95 0.99 0.999 0.9999 0.99999 1.0];
bitsPerVal = zeros(1,5);
nValTot = 0;

for f = 0:NF-1
    bf = fullfile(dataDir, sprintf('frame_%d.bin', f));
    o = struct('txSelect',1:12,'removeDC',true,'fx16EffectiveBits',16);
    evalc('[cube, config, ~] = loadColoRadarFrame(bf, o);');
    fx = compress_fx16(rangeFFT(preprocessing(cube, config), config), config);
    R = double(fx.real_part(:,:,1:NRX)); I = double(fx.imag_part(:,:,1:NRX));
    [nB,nR,nC] = size(R); nVal = nB*nR*nC*2; nValTot = nValTot + nVal;

    sets = cell(1,5);
    sets{1} = [R(:); I(:)];                         % no prediction
    sets{2} = drhe_res(R,I,1);
    sets{3} = drhe_res(R,I,Nt);
    sets{4} = lpc_res(R,I,1,1);
    sets{5} = lpc_res(R,I,Nt,Nt);

    for k = 1:5
        v = sets{k};
        H(k,:) = H(k,:) + histcounts(s4of(v), -0.5:1:15.5);
        bitsPerVal(k) = bitsPerVal(k) + sum(hb(v,hl));
        MAGQ(k,:) = MAGQ(k,:) + quantile(abs(v), q);
    end
    fprintf('  frame %d done\n', f);
end

MAGQ = MAGQ / NF;
bitsPerVal = bitsPerVal / nValTot;

writematrix(H,          [outDir 'fig_s4_hist.csv']);
writematrix(MAGQ,       [outDir 'fig_mag_quantiles.csv']);
writematrix(bitsPerVal, [outDir 'fig_bits_per_val.csv']);

names = {'no prediction','DRHE lag 1','DRHE lag 12','LPC lag 1,2','LPC lag 12,24'};
fprintf('\n%-16s %8s %8s %10s %10s\n','config','b/val','CR','med|res|','p99|res|');
for k=1:5
    fprintf('%-16s %8.3f %8.3f %10.1f %10.1f\n', names{k}, bitsPerVal(k), 16/bitsPerVal(k), MAGQ(k,1), MAGQ(k,5));
end
fprintf('\nS4 histograms (%% of values):\n      ');
for i=0:11, fprintf('%6d', i); end; fprintf('\n');
for k=1:5
    fprintf('%-14s', names{k});
    for i=1:12, fprintf('%6.2f', 100*H(k,i)/sum(H(k,:))); end
    fprintf('\n');
end
fprintf('\nWrote CSVs to %s\n', outDir);

% ---------- helpers ----------
function d = drhe_res(R,I,lag)
    [nB,nR,nC]=size(R); a=0.6; b=0.4; d=[];
    for c=1:nC
        for off=1:lag
            idx=off:lag:nR;
            pmp=zeros(nB,1); pm=zeros(nB,1); ppp=zeros(nB,1); pp=zeros(nB,1); pp2=zeros(nB,1);
            for kk=1:numel(idx)
                m=idx(kk); re=R(:,m,c); im=I(:,m,c);
                cm=sqrt(re.^2+im.^2); cp=atan2(im,re);
                mp=a*pmp+(1-a)*pm;
                php=b*ppp+(2-b)*pp-pp2;
                php(php>pi)=php(php>pi)-2*pi; php(php<-pi)=php(php<-pi)+2*pi;
                d=[d; wrap16(re-round(mp.*cos(php))); wrap16(im-round(mp.*sin(php)))]; %#ok<AGROW>
                pp2=pp; pp=cp; ppp=php; pm=cm; pmp=mp;
            end
        end
    end
end

function d = lpc_res(R,I,L1,Lstep)
    [nB,nR,nC]=size(R); d=[]; L2=L1+Lstep; N=nR;
    for c=1:nC
        for part=1:2
            if part==1, X=squeeze(R(:,:,c)); else, X=squeeze(I(:,:,c)); end
            R0=sum(X.^2,2);
            R1=sum(X(:,1:N-L1).*X(:,1+L1:N),2);
            R2=sum(X(:,1:N-L2).*X(:,1+L2:N),2);
            dt=R0.^2-R1.^2; a1=zeros(nB,1); a2=zeros(nB,1); ok=dt~=0;
            a1(ok)=(R1(ok).*(R0(ok)-R2(ok)))./dt(ok);
            a2(ok)=(R0(ok).*R2(ok)-R1(ok).^2)./dt(ok);
            bad=~ok|(abs(a2)>=1)|(abs(a1)>=(1-a2)); a1(bad)=0; a2(bad)=0;
            Xm1=[zeros(nB,L1) X(:,1:N-L1)];
            Xm2=[zeros(nB,L2) X(:,1:N-L2)];
            D=wrap16(X-round(a1.*Xm1+a2.*Xm2));
            d=[d; D(:)]; %#ok<AGROW>
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
