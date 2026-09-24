import numpy as np, json
from indep import *
Rs,Is=load_stim()
out={}; coefs={}
for (L1,L2) in [(1,2),(12,24)]:
    A1=[];A2=[];G=[]
    for f in range(50):
        for c in range(4):
            for X in (Rs[f][:,:,c], Is[f][:,:,c]):
                D,_,a1,a2=lpc_res(X,L1,L2)
                A1+=list(a1);A2+=list(a2)
                # per-bin energy ratio residual/raw (prediction gain)
                e0=(X**2).sum(1); e1=(D**2).sum(1)
                G+=list(e1/np.maximum(e0,1))
    A1=np.array(A1);A2=np.array(A2);G=np.array(G)
    coefs[f'{L1},{L2}']=dict(a1=A1.tolist(),a2=A2.tolist())
    out[f'{L1},{L2}']=dict(a1_min=A1.min(),a1_max=A1.max(),a2_min=A2.min(),a2_max=A2.max(),
        a1_med=float(np.median(A1)),a2_med=float(np.median(A2)),
        mean_abs_a1=float(np.abs(A1).mean()),mean_abs_a2=float(np.abs(A2).mean()),
        frac_small=float(((np.abs(A1)+np.abs(A2))<0.1).mean()),
        resid_energy_ratio_median=float(np.median(G)), resid_energy_ratio_mean=float(G.mean()),
        frac_worse_than_raw=float((G>1).mean()))
for k,v in out.items(): print(k,{a:round(b,4) for a,b in v.items()})

# coefficient lists for fig_lpccoef.pdf (paper/mkfig_story.py)
json.dump(coefs,open('lpc_coefs.json','w'))
