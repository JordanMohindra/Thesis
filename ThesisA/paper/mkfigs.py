import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np, csv

plt.rcParams.update({"font.size": 8, "font.family": "serif",
                     "axes.grid": True, "grid.alpha": 0.3, "grid.linewidth": 0.5})

# ---------- Figure 1: waterfall of bits/value ----------
fig, ax = plt.subplots(figsize=(3.4, 2.3))
labels = ["int16\ncontainer", "occupied\nrange", "after S4+\nHuffman", "after TDM\nprediction"]
levels = [16.0, 9.77, 4.586, 4.240]
drops  = [levels[i] - levels[i+1] for i in range(3)]
colors = ["#6b7b8c", "#c46d5e", "#4d7a5a"]
ax.bar(0, levels[0], width=0.6, color="#33414f", zorder=3)
for i in range(3):
    ax.bar(i+1, drops[i], bottom=levels[i+1], width=0.6, color=colors[i], zorder=3)
    ax.plot([i-0.3, i+1.3], [levels[i+1]]*2, color="0.35", lw=0.7, ls=":", zorder=2)
    ax.annotate(f"$\\div${levels[i]/levels[i+1]:.2f}", (i+1, levels[i+1]+drops[i]/2),
                ha="center", va="center", fontsize=7, color="white", zorder=4)
for i, v in enumerate(levels):
    ax.text(i, v + 0.35, f"{v:.2f}", ha="center", fontsize=7)
ax.set_xticks(range(4)); ax.set_xticklabels(labels, fontsize=7)
ax.set_ylabel("bits per value", labelpad=2); ax.set_ylim(0, 18)
ax.set_title("Where the compression ratio comes from", fontsize=8)
fig.tight_layout(pad=0.4)
fig.subplots_adjust(left=0.16)
fig.savefig("fig_waterfall.pdf")

# ---------- Figure 2: per-frame CR, 4 designs ----------
M = np.loadtxt("/mnt/user-data/uploads/Fifth_Year/Thesis/ThesisA/Matlab_Sim/_runlogs/perframe_cr4.csv",
               delimiter=",")
fig, ax = plt.subplots(figsize=(3.4, 2.3))
names = ["DRHE, lag 1", "LPC, lags 1,2", "DRHE, lag $n_{Tx}$", "LPC, lags $n_{Tx},2n_{Tx}$"]
sty = [("#8a8f98", "--"), ("#b08a4a", "--"), ("#2f6d4f", "-"), ("#8c4a3f", "-")]
for j in range(4):
    ax.plot(np.arange(50), M[:, j], color=sty[j][0], ls=sty[j][1], lw=1.1, label=names[j])
ax.set_xlabel("frame"); ax.set_ylabel("compression ratio")
ax.set_title("Per-frame compression ratio, 50 frames", fontsize=8)
ax.legend(fontsize=6, ncol=2, loc="lower left", framealpha=0.9)
ax.set_ylim(3.15, 3.95)
fig.tight_layout(pad=0.3)
fig.savefig("fig_perframe.pdf")

# ---------- Figure 3: S4 histogram ----------
pct = {0:11.50,1:21.52,2:31.51,3:22.97,4:6.86,5:2.42,6:1.43,7:1.08,8:0.65,9:0.06}
ln  = [4,3,2,2,2,5,6,7,8,9,10,11,14,14,13,12]
fig, ax = plt.subplots(figsize=(3.4, 2.1))
ks = sorted(pct)
ax.bar(ks, [pct[k] for k in ks], color="#40607d", width=0.7, zorder=3)
ax.set_xlabel("S4 category"); ax.set_ylabel("% of residuals")
ax2 = ax.twinx()
ax2.plot(ks, [ln[k]+k for k in ks], color="#b5553f", marker="o", ms=2.5, lw=1.0, zorder=4)
ax2.set_ylabel("code cost (bits)", color="#b5553f"); ax2.grid(False)
ax2.tick_params(axis="y", colors="#b5553f")
ax.set_title("DRHE residual categories and their cost", fontsize=8)
ax.set_xticks(ks)
fig.tight_layout(pad=0.3)
fig.savefig("fig_s4.pdf")
print("ok")
