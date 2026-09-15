%% AUDIT: is the predictor being applied across the wrong axis?
% loadColoRadarFrame flattens the ramp axis as ramp = c*Nt + t, i.e. TX is the
% FASTEST-varying index. So ramp m and ramp m-1 are almost always DIFFERENT TX
% antennas, at different physical positions on the array. The DRHE phase
% predictor assumes a constant phase increment between successive ramps; a TX
% change injects the array steering phase, which breaks that assumption.
%
% Variant A : as-shipped order (TX fastest)          ramp = c*Nt + t
% Variant B : chirp-loop fastest, per-TX blocks      ramp = t*Nc + c
% Variant C : a single TX only (pure slow-time, 16 ramps)

clear; clc;
dataDir = 'D:\Jordan''s Thesis\cascade\adc_samples\data';
hl = [4,3,2,2,2,5,6,7,8,9,10,11,14,14,13,12];
NF = 3; NRX = 4; Ns=256; Nc=16; Nr=16; Nt=12;

res = struct('name',{},'raw',{},'drhe',{});

for v = 1:3
    switch v
        case 1, nm='A: TX fastest (as shipped)';  o=struct('txSelect',1:12);
        case 2, nm='B: chirp-loop fastest';       o=struct('txSelect',1:12);
        case 3, nm='C: single TX (16 ramps)';     o=struct('txSelect',1);
    end
    o.removeDC=true; o.fx16EffectiveBits=16;
    br=[]; bd=[];
    for f = 0:NF-1
        bf = fullfile(dataDir, sprintf('frame_%d.bin', f));
        evalc('[cube, config, ~] = loadColoRadarFrame(bf, o);');
        if v==2
            % undo the TX-fastest flattening and redo it TX-slowest
            c4 = reshape(cube, [Ns, Nt, Nc, Nr]);      % [s, t, c, rx]
            c4 = permute(c4, [1 3 2 4]);               % [s, c, t, rx]
            cube = reshape(c4, [Ns, Nc*Nt, Nr]);
        end
        fx = compress_fx16(rangeFFT(preprocessing(cube, config), config), config);
        R = double(fx.real_part(:,:,1:NRX)); I = double(fx.imag_part(:,:,1:NRX));
        [nB,nR,nC]=size(R); nVal=nB*nR*nC*2;
        br(end+1) = sum(hb([R(:);I(:)],hl))/nVal;                        %#ok<SAGROW>
        dR=zeros(nB,nR,nC); dI=zeros(nB,nR,nC); a=0.6; b=0.4;
        for c=1:nC
            pmp=zeros(nB,1); pm=zeros(nB,1); ppp=zeros(nB,1); pp=zeros(nB,1); pp2=zeros(nB,1);
            for m=1:nR
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
        bd(end+1) = sum(hb([dR(:);dI(:)],hl))/nVal;                      %#ok<SAGROW>
    end
    res(v).name=nm; res(v).raw=mean(br); res(v).drhe=mean(bd);
    fprintf('  %s done\n', nm);
end

fprintf('\n=================================================================\n');
fprintf('  EFFECT OF RAMP ORDERING ON DRHE PREDICTION (%d frames, %d RX)\n', NF, NRX);
fprintf('=================================================================\n');
for v=1:3
    fprintf('  %-28s  no-pred %6.3f b  DRHE %6.3f b  CR %.3f  pred-gain %.3fx\n', ...
        res(v).name, res(v).raw, res(v).drhe, 16/res(v).drhe, res(v).raw/res(v).drhe);
end
fprintf('=================================================================\n');

function w = wrap16(v), w = mod(v+32768,65536)-32768; end
function s = s4of(v)
    av=abs(v); s=zeros(size(v)); nz=av>0; s(nz)=min(15,floor(log2(av(nz)))+1);
end
function b = hb(v, hl)
    s4=s4of(v); b=zeros(size(v));
    for i=0:15, mk=(s4==i); b(mk)=hl(i+1)+i; end
end
