"""Pipeline schedule of one DRHE sample, read from the Vitis HLS schedule reports
(*.verbose.sched.rpt): (a) DRHE-1 as built (closed loop), (b) the same design with
the polar conversion driven from the input sample (open loop). Bars are the first
and last pipeline stage holding an operation of that phase."""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Patch
plt.rcParams.update({"font.size": 8.5, "font.family": "serif",
                     "axes.spines.top": False, "axes.spines.right": False})
PRED="#2F5D7C"; POL="#B5553F"; PACK="#2F6D4F"; IO="#8A8F98"
rows = ["read sample, load state", "IIR prediction (fmul, fadd)", "wrap phase to $[-\\pi,\\pi]$",
        "sin, cos, $\\hat a\\cos$, $\\hat a\\sin$, round", "residual, clamp, reconstruct",
        "magnitude: int$\\to$float, $re^2+im^2$, sqrt", "phase: atan2", "S4, Huffman, pack, store"]
col  = [IO, PRED, PRED, PRED, PRED, POL, POL, PACK]
closed = [(1,3),(4,14),(14,19),(18,31),(28,32),(29,50),(32,59),(56,60)]   # drhe_compress (DRHE-1)
opened = [(1,3),(4,14),(14,19),(18,29),(30,31),(3,22),(6,31),(31,34)]     # ABL_LOOP=1 variant
fig, axes = plt.subplots(1, 2, figsize=(6.4, 2.9), sharey=True, gridspec_kw=dict(width_ratios=[1.35, 1]))
for ax, spans, depth, title in ((axes[0], closed, 58, "(a) closed loop, as built: depth 58"),
                                (axes[1], opened, 32, "(b) open loop: depth 32")):
    for i, (a, b) in enumerate(spans):
        ax.barh(i, b - a + 1, left=a - 0.5, color=col[i], height=0.62)
    ax.axvline(depth + 0.5, color="0.3", ls="--", lw=0.8)
    ax.set_xlim(0, 62); ax.set_xlabel("pipeline stage (clock cycle)")
    ax.set_title(title, fontsize=8.3, loc="left")
axes[0].set_yticks(range(len(rows))); axes[0].set_yticklabels(rows, fontsize=7.2); axes[0].invert_yaxis()
fig.legend(handles=[Patch(color=PRED, label="prediction"), Patch(color=POL, label="polar conversion (state update)"),
                    Patch(color=PACK, label="entropy coding"), Patch(color=IO, label="I/O, memory")],
           loc="lower center", ncol=4, fontsize=7, frameon=False, bbox_to_anchor=(0.55, -0.01))
fig.tight_layout(rect=(0, 0.07, 1, 1)); fig.savefig("fig_sched.pdf")
