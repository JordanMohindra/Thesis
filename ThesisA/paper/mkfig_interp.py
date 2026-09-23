import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
plt.rcParams.update({"font.size": 9, "font.family": "serif",
                     "axes.grid": True, "grid.alpha": 0.28, "grid.linewidth": 0.5,
                     "axes.spines.top": False, "axes.spines.right": False})
ACC="#2F5D7C"; WARM="#B5553F"; GREEN="#2F6D4F"; SLATE="#8A8F98"; GOLD="#B08A4A"

# ---------- Latency on one logarithmic time axis ----------
items = [  # (seconds, label, colour, row)
 (580e-9,  "DRHE pipeline depth\n58 cyc = 580 ns", GREEN, 0),
 (230e-9,  "Kiem pipeline depth\n23 cyc = 230 ns", SLATE, 1),
 (3.19e-6, "DRHE: added after\nlast ramp ≈ 3.2 µs", GREEN, 2),
 (78.5e-6, "one ramp interval\n78.5 µs", GOLD, 3),
 (79.4e-6, "Kiem system drain \n(incl. FFT, DMA) 79 µs ", SLATE, 0, "right"),
 (1.24e-3, "LPC lags 1,2: added\nafter last ramp 1.2 ms", WARM, 1),
 (3.01e-3, "LPC lags $n_{Tx}$: added\nafter last ramp 3.0 ms", WARM, 2),
 (15.07e-3," frame acquisition\n 15.1 ms", GOLD, 0, "left"),
 (15e-3,   "Kiem compression\nbudget 15 ms", SLATE, 3),
 (200e-3,  "frame period at 5 Hz\n200 ms", GOLD, 1),
]
fig, ax = plt.subplots(figsize=(6.3, 3.1))
ax.set_xscale("log"); ax.set_xlim(1e-7, 1)
ax.set_ylim(-0.6, 4.3); ax.set_yticks([]); ax.spines["left"].set_visible(False)
ax.axhline(-0.3, color="0.3", lw=0.8)
for it in items:
    t,lab,c,r = it[:4]; ha = it[4] if len(it)>4 else "center"
    y = 0.35 + r*1.0
    ax.plot([t,t],[-0.3,y-0.05], color=c, lw=0.9)
    ax.plot(t,-0.3,"o",color=c,ms=3.5,zorder=4)
    ax.text(t, y, lab, ha=ha, va="bottom", fontsize=6.8, color=c)
ax.axvspan(78.5e-6, 1, color=GOLD, alpha=0.06, lw=0)
ax.text(2.2e-4, 4.1, "sensor time-scales", fontsize=7, color=GOLD, ha="left", style="italic")
ax.set_xlabel("time (log scale)")
ax.set_xticks([1e-7,1e-6,1e-5,1e-4,1e-3,1e-2,1e-1,1])
ax.set_xticklabels(["100 ns","1 µs","10 µs","100 µs","1 ms","10 ms","100 ms","1 s"])
ax.grid(axis="y", visible=False)
fig.tight_layout(pad=0.3); fig.savefig("fig_latency_scale.pdf")

# ---------- Throughput: capacity against requirement ----------
labs = ["DRHE\n(II=2, 100 MHz)","DRHE\n(at $F_{\\max}$)","LPC lags $n_{Tx}$\n(100 MHz)","ideal II=1\n(128 b/cyc)","Kiem\n(theoretical)"]
cap  = [5.136, 4.205, 0.967, 12.8, 12.8]
cols = [GREEN, GREEN, WARM, SLATE, SLATE]
fig, ax = plt.subplots(figsize=(6.3, 2.9))
x = np.arange(len(labs))
b = ax.bar(x, cap, color=cols, width=0.6, zorder=3)
for i,v in enumerate(cap):
    ax.text(i, v*1.12, f"{v:g}", ha="center", fontsize=7.5)
ax.set_yscale("log"); ax.set_ylim(0.1, 40); ax.set_xlim(-0.5, 5.5)
ax.set_xticks(x); ax.set_xticklabels(labs, fontsize=7.5)
ax.set_ylabel("Gbit/s (log scale)")
reqs = [(0.2087,"ColoRadar, 4 RX: 0.209"),(0.8349,"ColoRadar, 16 RX: 0.835"),(3.196,"Kiem's sensor: 3.2")]
for v,l in reqs:
    ax.axhline(v, color="0.35", ls="--", lw=0.8, zorder=2)
    ax.text(4.4, v*1.07, l.replace(": ",":\n"), fontsize=6.8, ha="left", va="bottom", color="0.25")
fig.tight_layout(pad=0.3); fig.savefig("fig_headroom.pdf")
