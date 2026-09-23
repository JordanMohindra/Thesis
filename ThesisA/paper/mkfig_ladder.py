"""Resources at each step from DRHE-1 to the Kiem replica (post-route), from
hw_numbers.json written by collect_impl.py."""
import json, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
plt.rcParams.update({"font.size": 8, "font.family": "serif",
                     "axes.spines.top": False, "axes.spines.right": False})
D = json.load(open("../hwdata/hw_numbers.json"))
steps = [("drhe1", "DRHE-1\n(as built)"), ("abl_p1", "unsigned\noffset"), ("abl_p2", "58-bit\npacker"),
         ("abl_p2r", "no reset\nwrite: II=1"), ("abl_fxc", "fixed\npoint"), ("abl_k", "open loop\n= replica")]
K = dict(LUT=45892, FF=9243, DSP=44, BRAM=20)
fig, axes = plt.subplots(1, 4, figsize=(6.5, 2.6))
cols = ["#8A8F98", "#2F5D7C", "#2F5D7C", "#B5553F", "#2F6D4F", "#2F6D4F"]
for ax, (key, title) in zip(axes, [("LUT", "LUTs"), ("FF", "flip-flops"), ("DSP", "DSP slices"), ("BRAM", "BRAM_18K")]):
    v = [D[s][key] if s in D and D[s].get(key) is not None else 0 for s, _ in steps]
    ax.bar(range(len(v)), v, color=cols, width=0.7)
    ax.axhline(K[key], color="0.2", ls="--", lw=0.8)
    ax.set_title(title, fontsize=8.5)
    ax.set_xticks(range(len(v))); ax.set_xticklabels([str(i) for i in range(len(v))], fontsize=7)
    ax.tick_params(axis="y", labelsize=7)
    ax.text(len(v) - 0.5, K[key], "Kiem", fontsize=6.5, va="bottom", ha="right", color="0.2")
fig.text(0.5, 0.01, "step: 0 DRHE-1 · 1 unsigned offset · 2 58-bit packer · 3 II=1 · 4 fixed point · 5 open loop (replica)",
         ha="center", fontsize=7)
fig.tight_layout(rect=(0, 0.06, 1, 1)); fig.savefig("fig_ladder.pdf")
