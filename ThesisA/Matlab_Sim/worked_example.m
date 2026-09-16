%% Worked residual example from real ColoRadar data, for report section 3.1.
clear; clc;
dataDir = 'D:\Jordan''s Thesis\cascade\adc_samples\data';
hl = [4,3,2,2,2,5,6,7,8,9,10,11,14,14,13,12];
Nt = 12;  W0 = 169;  WN = 16;      % window of ramps to print (1-based)

o = struct('txSelect',1:12,'removeDC',true,'fx16EffectiveBits',16);
evalc('[cube, config, ~] = loadColoRadarFrame(fullfile(dataDir,''frame_0.bin''), o);');
fx = compress_fx16(rangeFFT(preprocessing(cube, config), config), config);
R1 = double(fx.real_part(:,:,1)); I1 = double(fx.imag_part(:,:,1));

m_all = sqrt(R1.^2 + I1.^2);
[~, bin] = max(mean(m_all,2));
fprintf('=== range bin n = %d (channel 1), mean |x| = %.1f ===\n', bin, mean(m_all(bin,:)));
fprintf('=== window: ramps %d..%d (both predictors fully converged) ===\n\n', W0-1, W0+WN-2);

re = R1(bin,:); im = I1(bin,:);
[p1re,~,d1re,~]   = drhe_trace(re,im,1);
[p12re,~,d12re,~] = drhe_trace(re,im,Nt);

fprintf('%3s %3s %7s | %8s %7s %3s %5s | %8s %7s %3s %5s\n', ...
    'm','TX','x','pred_1','d_1','S4','bits','pred_12','d_12','S4','bits');
tot1=0; tot12=0;
for m = W0:W0+WN-1
    s1 = s4of(d1re(m)); s12 = s4of(d12re(m));
    b1 = hl(s1+1)+s1;  b12 = hl(s12+1)+s12;
    tot1=tot1+b1; tot12=tot12+b12;
    fprintf('%3d %3d %7d | %8d %7d %3d %5d | %8d %7d %3d %5d\n', ...
        m-1, mod(m-1,Nt), re(m), p1re(m), d1re(m), s1, b1, p12re(m), d12re(m), s12, b12);
end
fprintf('%38s %13d %24d\n','TOTAL bits, 16 samples:',tot1,tot12);
fprintf('%38s %13.2f %24.2f\n','bits per value:',tot1/WN,tot12/WN);
fprintf('%38s %13.3f %24.3f\n','CR vs 16 raw bits:',16/(tot1/WN),16/(tot12/WN));

fprintf('\npolar view, same bin and window\n');
fprintf('%3s %3s %8s %9s | %11s %11s | %11s %11s\n', ...
    'm','TX','|x|','angle','|x|-|x[m-1]|','dtheta_1','|x|-|x[m-12]|','dtheta_12');
w = @(x) mod(x+pi,2*pi)-pi;
for m = W0:W0+WN-1
    mg=sqrt(re(m)^2+im(m)^2); ph=atan2(im(m),re(m));
    fprintf('%3d %3d %8.1f %9.3f | %11.1f %11.3f | %11.1f %11.3f\n', m-1, mod(m-1,Nt), mg, ph, ...
        mg-sqrt(re(m-1)^2+im(m-1)^2),  w(ph-atan2(im(m-1),re(m-1))), ...
        mg-sqrt(re(m-12)^2+im(m-12)^2), w(ph-atan2(im(m-12),re(m-12))));
end

% ---- aggregate bit budget, whole frame, 4 RX, computed per (bin,channel) ----
d1all=[]; d12all=[]; rawall=[];
for c=1:4
    Rc=double(fx.real_part(:,:,c)); Ic=double(fx.imag_part(:,:,c));
    rawall=[rawall; Rc(:); Ic(:)];                                     %#ok<AGROW>
    for n=1:size(Rc,1)
        [~,~,a,b] = drhe_trace(Rc(n,:),Ic(n,:),1);  d1all =[d1all;  a(:); b(:)];  %#ok<AGROW>
        [~,~,a,b] = drhe_trace(Rc(n,:),Ic(n,:),Nt); d12all=[d12all; a(:); b(:)];  %#ok<AGROW>
    end
end

for k=1:3
    switch k
        case 1, v=rawall; nm='raw FX16 values (no prediction)';
        case 2, v=d1all;  nm='DRHE residuals, lag 1';
        case 3, v=d12all; nm='DRHE residuals, lag 12';
    end
    s=s4of(v); N=numel(v); per=zeros(1,16);
    for i=0:15, per(i+1)=sum(s==i)*(hl(i+1)+i); end
    tb=sum(per);
    fprintf('\n=== bit budget: %s ===\n', nm);
    fprintf('%3s %12s %10s %9s %12s %8s\n','S4','|v| range','count','%%values','bits','%%bits');
    for i=0:15
        c=sum(s==i);
        if c>0
            if i==0, rng='0'; elseif i==1, rng='1'; else, rng=sprintf('%d-%d',2^(i-1),2^i-1); end
            fprintf('%3d %12s %10d %9.2f %12d %8.2f\n', i, rng, c, 100*c/N, per(i+1), 100*per(i+1)/tb);
        end
    end
    fprintf('%3s %12s %10d %9.2f %12d %8.2f  -> %.3f b/val, CR %.3f\n','all','',N,100,tb,100,tb/N,16/(tb/N));
end

function [pre,pim,dre,dim] = drhe_trace(re,im,lag)
    nR=numel(re); a=0.6; b=0.4;
    pre=zeros(1,nR); pim=zeros(1,nR); dre=zeros(1,nR); dim=zeros(1,nR);
    for off=1:lag
        idx=off:lag:nR; pmp=0; pm=0; ppp=0; pp=0; pp2=0;
        for kk=1:numel(idx)
            m=idx(kk);
            cm=sqrt(re(m)^2+im(m)^2); cp=atan2(im(m),re(m));
            mp=a*pmp+(1-a)*pm;
            php=b*ppp+(2-b)*pp-pp2;
            if php>pi, php=php-2*pi; elseif php<-pi, php=php+2*pi; end
            pre(m)=round(mp*cos(php)); pim(m)=round(mp*sin(php));
            dre(m)=wrap16(re(m)-pre(m)); dim(m)=wrap16(im(m)-pim(m));
            pp2=pp; pp=cp; ppp=php; pm=cm; pmp=mp;
        end
    end
end
function w = wrap16(v), w = mod(v+32768,65536)-32768; end
function s = s4of(v)
    av=abs(v); s=zeros(size(v)); nz=av>0; s(nz)=min(15,floor(log2(av(nz)))+1);
end
