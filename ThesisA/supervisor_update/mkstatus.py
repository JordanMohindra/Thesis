import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.patches import Rectangle

plt.rcParams.update({"font.size": 9, "font.family": "serif"})
DONE="#2F6D4F"; PART="#B08A4A"; TODO="#C9CDD2"; ACC="#2F5D7C"

rows = [
    ("Phase 1  MATLAB reference", 1.00, "50 frames, 8 algorithms, re-verified"),
    ("Phase 2  HLS C-simulation", 1.00, "4 designs, 50 frames, all bit-exact"),
    ("Phase 3  Synthesis + RTL co-sim", 1.00, "4 designs, resources and exact latency"),
    ("Phase 4  On silicon", 0.00, "needs board access"),
    ("", None, ""),
    ("Obj 1  Mitigate quantisation error", 0.35, "root cause found; fix not yet implemented"),
    ("Obj 2  Broaden algorithm comparison", 0.65, "LPC and the no-prediction baseline done"),
    ("Obj 3  Full compress + decompress chain", 0.85, "both directions built and verified in simulation"),
]

fig, ax = plt.subplots(figsize=(7.2, 3.3))
y = 0
yticks, ylabels = [], []
for label, frac, note in rows:
    if frac is None:
        y -= 0.55
        continue
    col = DONE if frac >= 0.99 else (PART if frac > 0 else TODO)
    ax.add_patch(Rectangle((0, y-0.3), 1.0, 0.6, facecolor=TODO, edgecolor="none", zorder=2))
    ax.add_patch(Rectangle((0, y-0.3), frac, 0.6, facecolor=col, edgecolor="none", zorder=3))
    pct = f"{int(round(frac*100))}%"
    ax.text(1.035, y, pct, va="center", fontsize=8, color="0.25", ha="left")
    ax.text(1.42, y, note, va="center", fontsize=7.4, color="0.42")
    yticks.append(y); ylabels.append(label)
    y -= 1.0

ax.set_yticks(yticks); ax.set_yticklabels(ylabels, fontsize=8.6)
ax.set_xlim(0, 3.95); ax.set_ylim(y+0.55, 0.75)
ax.set_xticks([])
for s in ["top","right","bottom","left"]: ax.spines[s].set_visible(False)
ax.tick_params(length=0)
ax.text(0, 0.62, "Verification phases", fontsize=8.6, fontweight="bold", color=ACC)
ax.text(0, -4.03, "Thesis A objectives", fontsize=8.6, fontweight="bold", color=ACC)
fig.tight_layout(pad=0.3)
fig.savefig("fig_status.pdf")
print("ok")
