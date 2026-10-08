"""golden_check.py - decode the HLS C-simulation compressed bitstreams (fpga_kcu116/golden)
with an independent Python decoder and compare the residuals and LPC coefficient table
with indep.py. Confirms the bitstream format and byte order the board will produce."""
import numpy as np, struct, math
from indep import *
import os
G=os.path.join(os.path.dirname(os.path.abspath(__file__)),'..','fpga_kcu116','golden')+os.sep
def load(fn):
    g=open(G+fn,'rb').read(); nF=struct.unpack_from('<I',g,0)[0]; off=4; out=[]
    for _ in range(nF):
        nw=struct.unpack_from('<I',g,off)[0]; off+=4; out.append(g[off:off+32*nw]); off+=32*nw
    assert off==len(g); return out
KIEM_CODES=[(0x0005,4),(0x0001,3),(0x0002,2),(0x0000,2),(0x0003,2),(0x000D,5),(0x001D,6),(0x003D,7),(0x007D,8),(0x00FD,9),(0x01FD,10),(0x03FD,11),(0x3FFD,14),(0x1FFD,14),(0x0FFD,13),(0x07FD,12)]
# the TDM cores use the re-derived dictionaries (retrain_complete.json drhe12 / lpc1224), LSB-first
TABLES={'drhe':[(0x0003,3),(0x0001,2),(0x0000,1),(0x0007,4),(0x000F,5),(0x001F,6),(0x003F,7),(0x007F,8),(0x00FF,9),(0x01FF,10),(0x03FF,11),(0x1FFF,14),(0x3FFF,14),(0x07FF,13),(0x17FF,13),(0x0FFF,13)],
        'lpc':[(0x0003,3),(0x0000,1),(0x0001,2),(0x0007,4),(0x000F,5),(0x001F,6),(0x003F,7),(0x007F,8),(0x00FF,9),(0x01FF,10),(0x07FF,13),(0x17FF,13),(0x0FFF,13),(0x1FFF,13),(0x03FF,12),(0x0BFF,12)]}
CODES=KIEM_CODES
def bitsL(v):
    s=s4(v); return int((LEN[s]+s).sum())
class BR:
    def __init__(s,b): s.v=int.from_bytes(b,'little'); s.p=0
    def peek(s,n): return (s.v>>s.p)&((1<<n)-1)
    def take(s,n): x=s.peek(n); s.p+=n; return x
def sym(br):
    for k,(c,l) in enumerate(CODES):
        if br.peek(l)==c: br.p+=l; return k
    raise ValueError('bad code')
def val(br):
    S=sym(br)
    if S==0: return 0
    a=br.take(S)
    return a if a>>(S-1) else a-(1<<S)+1
Rs,Is=load_stim()
nval=192*128*4
for algo,fn in [('drhe','golden_drhe_tdm_compressed.bin'),('lpc','golden_lpc_tdm_compressed.bin')]:
    CODES=TABLES[algo]; LEN=np.array([l for _,l in CODES])
    gold=load(fn)
    for f in range(3):
        R,I=Rs[f],Is[f]
        if algo=='drhe':
            a,b=drhe_res(R,I,12)
            exp_bits=bitsL(np.concatenate([a.ravel(),b.ravel()]))
        else:
            res={};exp_bits=32768
            for c in range(4):
                for p,X in enumerate((R[:,:,c],I[:,:,c])):
                    D,_,a1,a2=lpc_res(X,12,24); res[(c,p)]=(D,a1,a2); exp_bits+=bitsL(D.ravel())
        nw=len(gold[f])//32
        br=BR(gold[f])
        if algo=='lpc':
            # coefficient table: per ch, per bin: a1re a2re a1im a2im (16 bits each)
            for c in range(4):
                for n in range(128):
                    w=[br.take(16) for _ in range(4)]
                    e1=int(np.round(res[(c,0)][1][n]*2**14))&0xFFFF; e2=int(np.round(res[(c,0)][2][n]*2**15))&0xFFFF
                    assert (w[0],w[1])==(e1,e2),(f,c,n,w,e1,e2)
        mism=0
        for r in range(192):
            for s_ in range(128):
                for c in range(4):
                    vr=val(br); vi=val(br)
                    if algo=='drhe': er,ei=a[s_,r,c],b[s_,r,c]
                    else: er,ei=res[(c,0)][0][s_,r],res[(c,1)][0][s_,r]
                    mism+= (vr!=er)+(vi!=ei)
        print(algo,'frame',f,'words',nw,'expected',math.ceil(exp_bits/256),'decoded bits',br.p,'residual mismatches',mism)
