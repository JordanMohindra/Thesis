import numpy as np, heapq
from indep import *
def huff_len(cnt):
    items=[(c,i,[i]) for i,c in enumerate(cnt) if c>0]
    L=np.zeros(len(cnt))
    if len(items)==1: L[items[0][1]]=1; return L
    heapq.heapify(items); k=1000
    while len(items)>1:
        a=heapq.heappop(items); b=heapq.heappop(items)
        for i in a[2]+b[2]: L[i]+=1
        heapq.heappush(items,(a[0]+b[0],k,a[2]+b[2])); k+=1
    return L
if __name__=='__main__':
    Rs,Is=load_stim()
    
    acc={}
    for f in range(5):
        R,I=Rs[f],Is[f]
        sets={'nopred':np.concatenate([R.ravel(),I.ravel()])}
        a,b=drhe_res(R,I,1); sets['drhe1']=np.concatenate([a.ravel(),b.ravel()])
        a,b=drhe_res(R,I,12); sets['drhe12']=np.concatenate([a.ravel(),b.ravel()])
        l=[];l2=[]
        for c in range(4):
            for X in (R[:,:,c],I[:,:,c]):
                l.append(lpc_res(X,1,2)[0].ravel()); l2.append(lpc_res(X,12,24)[0].ravel())
        sets['lpc12']=np.concatenate(l); sets['lpc1224']=np.concatenate(l2)
        for k,v in sets.items():
            s=s4(v); cnt=np.bincount(s,minlength=16); L=huff_len(cnt)
            ideal=(cnt*(L+np.arange(16))).sum()+16*4
            fixed=(cnt*(HL+np.arange(16))).sum()
            acc.setdefault(k,[0,0,0,0]); acc[k][0]+=fixed; acc[k][1]+=ideal; acc[k][2]+=v.size; acc[k][3]+=entropy(v)*v.size
    for k,(fx,idl,n,H) in acc.items():
        print(f'{k:8s} fixed {fx/n:.3f}  idealS4 {idl/n:.3f}  (saving {100*(1-idl/fx):.1f}%)  order0 {H/n:.3f}  fixed-over-H {100*(fx/H-1):.1f}%')
    