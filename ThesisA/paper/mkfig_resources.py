# Resource usage of the four designs, post-route (solid) against the HLS estimate (outline).
import json, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt, matplotlib.patches as mp
plt.rcParams.update({"font.size": 9, "font.family": "serif", "axes.grid": True, "grid.alpha": 0.28,
                     "grid.linewidth": 0.5, "axes.spines.top": False, "axes.spines.right": False})
D = json.load(open("../hwdata/hw_numbers.json"))
keys = ["drhe1", "drhe_n", "lpc1", "lpc_n"]
cs = ["#8A8F98", "#2F6D4F", "#B08A4A", "#B5553F"]
lbls = ["D$_1$", "D$_{n}$", "L$_{1,2}$", "L$_{n,2n}$"]
res = [("LUT", "LUT", "hLUT", 216960), ("FF", "FF", "hFF", 433920), ("BRAM (18K)", "BRAM", "hBRAM", 960), ("DSP", "DSP", "hDSP", 1824)]
fig, axs = plt.subplots(1, 4, figsize=(6.4, 2.8))
for ax, (nm, k, hk, cap) in zip(axs, res):
    for i, d in enumerate(keys):
        r = D.get(d, {})
        if r.get(hk) is not None:
            ax.bar(i, r[hk], width=0.7, fill=False, edgecolor=cs[i], lw=0.9, ls="--", zorder=3)
        if r.get(k) is not None:
            ax.bar(i, r[k], width=0.7, color=cs[i], zorder=4)
    ax.set_title(nm, fontsize=8.5)
    ax.set_xticks(range(4)); ax.set_xticklabels(lbls, fontsize=7)
    ax.tick_params(axis="y", labelsize=7)
    top = max([D.get(d, {}).get(hk) or 0 for d in keys] + [D.get(d, {}).get(k) or 0 for d in keys])
    ax.set_ylim(0, top * 1.15)
handles = [mp.Patch(color=cs[i], label=l) for i, l in enumerate(
    ["D$_1$: DRHE lag 1", "D$_n$: DRHE lag $n_{Tx}$", "L$_{1,2}$: LPC lags 1,2", "L$_{n,2n}$: LPC lags $n_{Tx}$,$2n_{Tx}$"])]
handles.append(mp.Patch(fill=False, edgecolor="0.3", ls="--", label="HLS estimate"))
fig.legend(handles=handles, fontsize=6.5, ncol=5, loc="lower center", frameon=False, bbox_to_anchor=(0.5, -0.02), columnspacing=1.0)
fig.tight_layout(pad=0.4, rect=[0, 0.09, 1, 1]); fig.savefig("fig_resources.pdf")
print("ok")
