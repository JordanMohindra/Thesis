import numpy as np, heapq
from indep import *
from idealdict import huff_len
def r4s4_bits(V):
    # V: [bins, cols]; runs along bins; JPEG-like ZRL (15,0) and EOB (0,0)
    B,C=V.shape; syms=[]; app=0
    for c in range(C):
        col=V[:,c]; nz=np.nonzero(col)[0]; prev=-1
        for i in nz:
            run=i-prev-1
            while run>15: syms.append(15*16+0); run-=16
            s=int(s4(np.array([col[i]]))[0]); syms.append(16*run+s); app+=s; prev=i
        if prev<B-1: syms.append(0)
    cnt=np.bincount(np.array(syms),minlength=256); L=huff_len(cnt)
    return int((cnt*L).sum())+app
Rs,Is=load_stim()
out={'drhe1':[], 'drhe12':[], 'nopred':[]}
inb=128*192*4*32
for f in range(0,50,5):
    R,I=Rs[f],Is[f]
    for k,(a,b) in {'nopred':(R,I),'drhe1':drhe_res(R,I,1),'drhe12':drhe_res(R,I,12)}.items():
        bb=r4s4_bits(a.reshape(128,-1))+r4s4_bits(b.reshape(128,-1))
        s=s4(np.concatenate([a.ravel(),b.ravel()])); cnt=np.bincount(s,minlength=16); L=huff_len(cnt)
        ideal_s4=(cnt*(L+np.arange(16))).sum()+64
        out[k].append((inb/bb, inb/ideal_s4))
for k,v in out.items():
    v=np.array(v); print(k,'R4S4+RLE ideal CR %.3f   S4-only ideal CR %.3f'%tuple(v.mean(0)))
