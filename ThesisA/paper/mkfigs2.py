import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

plt.rcParams.update({"font.size": 9, "font.family": "serif",
                     "axes.grid": True, "grid.alpha": 0.28, "grid.linewidth": 0.5,
                     "axes.spines.top": False, "axes.spines.right": False})

ACC="#2F5D7C"; WARM="#B5553F"; GREEN="#2F6D4F"; SLATE="#8A8F98"; GOLD="#B08A4A"
HL=[4,3,2,2,2,5,6,7,8,9,10,11,14,14,13,12]

names=["no prediction","DRHE lag 1","DRHE lag $n_{Tx}$","LPC lags 1,2","LPC lags $n_{Tx}$,$2n_{Tx}$"]
hist=np.array([
 [16.42,28.39,31.28,15.06,4.54,1.73,1.17,1.13,0.19,0.07,0,0],
 [11.50,21.52,31.51,22.97,6.86,2.42,1.43,1.08,0.65,0.06,0,0],
 [18.24,31.75,34.57,12.54,1.88,0.51,0.29,0.18,0.03,0.01,0,0],
 [16.92,29.16,31.64,14.43,3.69,1.79,1.37,0.67,0.28,0.05,0,0],
 [23.77,38.50,30.67, 5.81,0.91,0.19,0.07,0.07,0.01,0.00,0,0]])
bpv=np.array([4.586,4.821,4.240,4.543,4.102])
p99=np.array([80.6,102.4,15.8,63.4,8.2])
med=np.array([2.0,2.2,1.6,2.0,1.0])

# ---------- F1: S4 histogram comparison, 3 key configs ----------
fig, ax = plt.subplots(figsize=(6.0, 3.0))
w=0.26; ks=np.arange(12)
for j,(row,lab,col) in enumerate(zip([hist[0],hist[1],hist[2]],
        ["no prediction","DRHE, lag 1 (as originally implemented)","DRHE, lag $n_{Tx}$ (corrected)"],
        [SLATE,WARM,GREEN])):
    ax.bar(ks+(j-1)*w, row, width=w, label=lab, color=col, zorder=3)
ax.set_xlabel("S4 category  (0 = residual is zero, $k$ = residual needs $k$ bits)")
ax.set_ylabel("% of values")
ax.set_xticks(ks)
ax.legend(fontsize=7.5, frameon=False)
ax2=ax.twinx(); ax2.plot(ks,[HL[k]+k for k in ks],color="0.25",marker="o",ms=2.5,lw=0.9,ls="--",zorder=4)
ax2.set_ylabel("bits to code (dashed)",fontsize=8,color="0.25"); ax2.grid(False)
ax2.tick_params(axis="y",labelsize=8,colors="0.25")
fig.tight_layout(pad=0.4); fig.savefig("fig_s4compare.pdf")

# ---------- F2: residual magnitude, median and 99th percentile ----------
fig, ax = plt.subplots(figsize=(6.0, 2.7))
y=np.arange(5)[::-1]
cols=[SLATE,WARM,GREEN,GOLD,"#6B4E7D"]
ax.barh(y, p99, height=0.55, color=cols, zorder=3)
for i,(yy,v,m) in enumerate(zip(y,p99,med)):
    ax.text(v+3, yy, f"p99 = {v:.1f}  (median {m:.1f})", va="center", fontsize=7.5)
ax.set_yticks(y); ax.set_yticklabels(names, fontsize=8.5)
ax.set_xlabel("99th percentile of $|$residual$|$   (FX16 codes; smaller is better)")
ax.set_xlim(0,175); ax.grid(axis="y",alpha=0)
fig.tight_layout(pad=0.4); fig.savefig("fig_residmag.pdf")

# ---------- F3: bits per value bar ----------
fig, ax = plt.subplots(figsize=(6.0, 2.5))
ovh=0.167
tot=bpv.copy(); tot[3]+=ovh; tot[4]+=ovh
x=np.arange(5)
ax.bar(x, bpv, width=0.6, color=cols, zorder=3)
ax.bar([3,4],[ovh,ovh],bottom=[bpv[3],bpv[4]],width=0.6,color="0.75",zorder=3,
       hatch="///",edgecolor="white",linewidth=0.6,label="LPC coefficient table")
ax.axhline(bpv[0], color="0.3", ls=":", lw=1.0, zorder=1)
ax.text(2.0, bpv[0]+0.60, "no-prediction baseline", fontsize=7, ha="center", color="0.3")
ax.annotate("", xy=(2.0,bpv[0]), xytext=(2.0,bpv[0]+0.56),
            arrowprops=dict(arrowstyle="-", color="0.5", lw=0.6))
for i,v in enumerate(tot):
    ax.text(i, v+0.12, f"{v:.3f}\nCR {16/v:.3f}", ha="center", fontsize=7.5)
ax.set_xticks(x); ax.set_xticklabels(names, fontsize=8)
ax.set_ylabel("bits per value"); ax.set_ylim(0,6.5)
ax.legend(fontsize=7, frameon=False, loc="upper left", bbox_to_anchor=(0.0,1.0))
fig.tight_layout(pad=0.4); fig.savefig("fig_bpv.pdf")

# ---------- F4: waterfall ----------
fig, ax = plt.subplots(figsize=(5.4, 2.9))
labels=["int16\ncontainer","occupied\nrange","after S4 +\nHuffman","after TDM\nprediction"]
levels=[16.0,9.77,4.586,4.240]
drops=[levels[i]-levels[i+1] for i in range(3)]
colors=["#6b7b8c",WARM,GREEN]
ax.bar(0,levels[0],width=0.6,color="#33414f",zorder=3)
for i in range(3):
    ax.bar(i+1,drops[i],bottom=levels[i+1],width=0.6,color=colors[i],zorder=3)
    ax.plot([i-0.3,i+1.3],[levels[i+1]]*2,color="0.35",lw=0.7,ls=":",zorder=2)
    if drops[i] > 1.2:
        ax.annotate(f"$\\div${levels[i]/levels[i+1]:.2f}",(i+1,levels[i+1]+drops[i]/2),
                    ha="center",va="center",fontsize=8,color="white",zorder=4)
    else:
        ax.annotate(f"$\\div${levels[i]/levels[i+1]:.2f}",(i+1.38,levels[i+1]+drops[i]/2),
                    ha="left",va="center",fontsize=8,color=colors[i],zorder=4)
for i,v in enumerate(levels):
    dx = 0.0 if i < 3 else -0.38
    ax.text(i+dx,v+0.40,f"{v:.2f}",ha="center",fontsize=8)
ax.set_xticks(range(4)); ax.set_xticklabels(labels,fontsize=8)
ax.set_ylabel("bits per value",labelpad=2); ax.set_ylim(0,18); ax.set_xlim(-0.6,3.9)
fig.tight_layout(pad=0.4); fig.subplots_adjust(left=0.13)
fig.savefig("fig_waterfall.pdf")

# ---------- F5: per-frame CR ----------
M=np.loadtxt("/mnt/user-data/uploads/Fifth_Year/Thesis/ThesisA/Matlab_Sim/_runlogs/perframe_cr4.csv",delimiter=",")
fig, ax = plt.subplots(figsize=(6.0, 3.0))
sty=[(SLATE,"--","DRHE, lag 1"),(GOLD,"--","LPC, lags 1,2"),
     (GREEN,"-","DRHE, lag $n_{Tx}$"),(WARM,"-","LPC, lags $n_{Tx}$,$2n_{Tx}$")]
for j,(c,l,lab) in enumerate(sty):
    ax.plot(np.arange(50),M[:,j],color=c,ls=l,lw=1.2,label=lab)
ax.set_xlabel("frame index"); ax.set_ylabel("compression ratio")
ax.legend(fontsize=7.5,ncol=4,loc="lower center",bbox_to_anchor=(0.5,1.01),frameon=False,
          columnspacing=1.2,handlelength=1.8)
ax.set_ylim(3.15,3.90)
fig.tight_layout(pad=0.4); fig.savefig("fig_perframe.pdf")

# ---------- F6: resource comparison ----------
fig, axs = plt.subplots(1,4,figsize=(6.4,2.7))
res=[("LUT",[115532,115736,80528,86298],216960),
     ("FF",[57105,57263,17393,23154],433920),
     ("BRAM (18K)",[40,80,256,192],960),
     ("DSP",[132,132,168,156],1824)]
lbls=["D$_1$","D$_{n}$","L$_{1,2}$","L$_{n,2n}$"]
cs=[SLATE,GREEN,GOLD,WARM]
for ax,(nm,vals,cap) in zip(axs,res):
    ax.bar(range(4),vals,color=cs,width=0.7,zorder=3)
    ax.set_title(nm,fontsize=8.5)
    ax.set_xticks(range(4)); ax.set_xticklabels(lbls,fontsize=7,rotation=0)
    ax.tick_params(axis="y",labelsize=7)
    ax.axhline(cap,color="0.4",ls=":",lw=0.9)
    ax.text(3.5,cap*1.02,"device",fontsize=6,ha="right",color="0.4")
    ax.set_ylim(0,cap*1.18)
import matplotlib.patches as mp
handles=[mp.Patch(color=cs[i],label=l) for i,l in enumerate(
    ["D$_1$: DRHE lag 1","D$_n$: DRHE lag $n_{Tx}$",
     "L$_{1,2}$: LPC lags 1,2","L$_{n,2n}$: LPC lags $n_{Tx}$,$2n_{Tx}$"])]
fig.legend(handles=handles,fontsize=7,ncol=4,loc="lower center",frameon=False,
           bbox_to_anchor=(0.5,-0.02),columnspacing=1.4)
fig.tight_layout(pad=0.4,rect=[0,0.09,1,1]); fig.savefig("fig_resources.pdf")
print("ok")
