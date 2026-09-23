"""HLS estimate against post-route LUTs, per part of the DRHE-n design.
HLS: drhe_tdm_compress_Pipeline_SAMPLE_LOOP_csynth.rpt (Instance + Expression +
Multiplexer + Register tables). Post-route: *_utilization_hierarchical_routed.rpt."""
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
plt.rcParams.update({"font.size": 8.5, "font.family": "serif",
                     "axes.spines.top": False, "axes.spines.right": False})
rows = [("loop body: packer, S4/Huffman,\nresidual, float$\\to$int, control", 60037, 9918),
        ("atan2 (2 shared units)",           40258, 11962),
        ("sin/cos (4 shared units)",          9400,  4834),
        ("fadd/fsub (12 IP cores)",           2568,  3124),
        ("fmul (16 IP cores)",                2160,  1699),
        ("int$\\to$float (4 IP cores)",          0,   987),
        ("sqrt (2 IP cores)",                    0,   958),
        ("round",                              616,   723),
        ("AXI interfaces, top level",          697,   599)]
lab = [r[0] for r in rows]; h = np.array([r[1] for r in rows]); v = np.array([r[2] for r in rows])
y = np.arange(len(rows))
fig, ax = plt.subplots(figsize=(6.3, 3.3))
ax.barh(y - 0.2, h, height=0.38, color="#B5553F", label="HLS estimate  (total 115,736)")
ax.barh(y + 0.2, v, height=0.38, color="#2F5D7C", label="after place and route  (total 34,804)")
for i in range(len(rows)):
    ax.text(h[i] + 600, y[i] - 0.2, f"{h[i]:,}", va="center", fontsize=6.8, color="#B5553F")
    ax.text(v[i] + 600, y[i] + 0.2, f"{v[i]:,}", va="center", fontsize=6.8, color="#2F5D7C")
ax.set_yticks(y); ax.set_yticklabels(lab, fontsize=7.4); ax.invert_yaxis()
ax.set_xlabel("LUTs"); ax.set_xlim(0, 70000)
ax.legend(frameon=False, fontsize=7.5, loc="lower right")
ax.grid(axis="x", alpha=0.25)
fig.tight_layout(pad=0.3); fig.savefig("fig_estimate.pdf")
