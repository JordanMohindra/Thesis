"""CR against prediction lag, all 50 frames, 4 RX, Kiem's fixed dictionary.
Per-frame CR with 256-bit padding, averaged over frames (same metric as HLS csim).
DRHE predicts ramp m from ramp m-L; LPC from ramps m-L and m-2L (coefficient table charged)."""
import numpy as np, json
from indep import *
Rs,Is=load_stim()
inb=128*192*4*32
cr=lambda b: inb/pad256(b)
out={'lags':[],'drhe':[],'lpc':[]}
out['nopred']=float(np.mean([cr(bits(np.concatenate([Rs[f].ravel(),Is[f].ravel()]))) for f in range(50)]))
for L in range(1,37):
    d=[];l=[]
    for f in range(50):
        a,b=drhe_res(Rs[f],Is[f],L); d.append(cr(bits(np.concatenate([a.ravel(),b.ravel()]))))
        bl=32768
        for c in range(4):
            for X in (Rs[f][:,:,c],Is[f][:,:,c]): bl+=bits(lpc_res(X,L,2*L)[0].ravel())
        l.append(cr(bl))
    out['lags'].append(L); out['drhe'].append(float(np.mean(d))); out['lpc'].append(float(np.mean(l)))
    print(L, round(out['drhe'][-1],5), round(out['lpc'][-1],5))
json.dump(out,open('lagsweep.json','w'),indent=1)
print('nopred',out['nopred'])
