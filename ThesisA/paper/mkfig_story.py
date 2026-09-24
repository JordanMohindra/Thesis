"""Figures for the narrative chapters (journey, replication, comparison).
Data sources:
  noise_sweep.csv, noise_sweep_peak.csv   - kiem_replication/results (MATLAB)
  lpc_coefs.json, retrain_complete.json    - verify/ (independent Python check)
Early Matlab_Sim synthetic-scene points are transcribed from
Matlab_Sim/main_final.log, kiem_final_with_noise.log and cr_preset_tune.txt.
"""
import json, csv
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

plt.rcParams.update({"font.size": 9, "font.family": "serif",
                     "axes.grid": True, "grid.alpha": 0.28, "grid.linewidth": 0.5,
                     "axes.spines.top": False, "axes.spines.right": False})
ACC = "#2F5D7C"; WARM = "#B5553F"; GREEN = "#2F6D4F"; SLATE = "#8A8F98"; GOLD = "#B08A4A"; PURP = "#6B4E7D"
V = "../verify_indep/"   # needs lpc_coefs.json (run coefstats.py) and retrain_complete.json
R = "../kiem_replication/results/"


def rd(p):
    with open(p) as f:
        r = list(csv.DictReader(f))
    return {k: np.array([float(x[k]) for x in r]) for k in r[0]}


hw = rd(V + "noise_sweep.csv")
pk = rd(R + "noise_sweep_peak.csv")

# ---------------- F1: CR against noise floor, two FX16 scalings ----------------
fig, ax = plt.subplots(figsize=(6.2, 4.1))
m = hw["NF_target_dBFS"] >= -120
ax.plot(hw["NF_target_dBFS"][m], hw["DRHE_fixed"][m], "-o", ms=3, color=ACC,
        label="DRHE, Kiem's FFT-core scaling (top 16 of 32 bits)")
ax.plot(pk["NF_target_dBFS"], pk["DRHE_fixed"], "-s", ms=3, color=WARM,
        label="DRHE, Matlab_Sim scaling (full-scale sinusoid = 32767)")
ax.plot(hw["NF_target_dBFS"][m], hw["LPC_raw"][m], ":x", ms=3, color=SLATE,
        label="LPC-Huffman (Meucci & Mancuso) on raw ADC, Kiem's scene")
early_nf = [-71.03, -70.70, -85.37, -95.08, -78.41, -82.45, -88.21, -90.03]
early_cr = [1.11, 1.10, 1.56, 2.08, 1.30, 1.44, 1.70, 1.79]
ax.plot(early_nf, early_cr, "D", ms=4.5, mfc="white", mec=GOLD, mew=1.2,
        label="early Matlab_Sim synthetic scenes (this thesis, 2026)")
ax.plot([-70.691], [3.25], "*", ms=12, color="#C0392B", label="Kiem, Table 3.5 (real data)")
ax.axhline(3.25, color="#C0392B", lw=0.7, ls=":")
ax.axvline(-75, color="0.4", lw=0.7, ls="--")
ax.text(-74.6, 3.9, "Kiem Table 3.2\nscene: $-75$ dBFS", fontsize=7, color="0.3")
ax.set_xlabel("noise floor after non-coherent integration (dBFS, full-scale sinusoid = 0 dB)")
ax.set_ylabel("compression ratio")
ax.set_xlim(-121, -59); ax.set_ylim(0, 4.3)
ax.legend(fontsize=6.8, frameon=False, loc="upper center", bbox_to_anchor=(0.5, -0.17), ncol=2)
fig.tight_layout(pad=0.4); fig.savefig("fig_kr_sweep.pdf")

# ---------------- F2: dictionary: Kiem's fixed vs retrained ----------------
rt = json.load(open(V + "retrain_complete.json"))
keys = ["nopred", "drhe1", "drhe12", "lpc12", "lpc1224"]
lab = ["no\nprediction", "DRHE\nlag 1", "DRHE\nlag $n_{Tx}$", "LPC\nlags 1,2", "LPC\nlags $n_{Tx}$,$2n_{Tx}$"]
fx = [rt[k]["kiem_test45"] for k in keys]
tr = [rt[k]["cr_test45"] for k in keys]
fig, ax = plt.subplots(figsize=(6.2, 2.9))
x = np.arange(5); w = 0.36
b1 = ax.bar(x - w / 2, fx, w, color=SLATE, label="Kiem's fixed dictionary (Appendix A)", zorder=3)
b2 = ax.bar(x + w / 2, tr, w, color=GREEN, label="dictionary re-derived on frames 0-4", zorder=3)
for xx, v in zip(x - w / 2, fx):
    ax.text(xx, v + 0.04, f"{v:.3f}", ha="center", fontsize=6.8)
for xx, v in zip(x + w / 2, tr):
    ax.text(xx, v + 0.04, f"{v:.3f}", ha="center", fontsize=6.8)
ax.set_xticks(x); ax.set_xticklabels(lab, fontsize=7.8)
ax.set_ylabel("compression ratio\n(frames 5-49, padded)")
ax.set_ylim(0, 4.9); ax.grid(axis="x", alpha=0)
ax.legend(fontsize=7, frameon=False, loc="upper left")
fig.tight_layout(pad=0.4); fig.savefig("fig_dict.pdf")

# ---------------- F3: LPC coefficient distribution ----------------
A = json.load(open(V + "lpc_coefs.json"))
fig, axs = plt.subplots(1, 2, figsize=(6.2, 2.5), sharey=True)
bins = np.linspace(-1.2, 1.5, 55)
for ax, key, title in [(axs[0], "a1", "$a_1$"), (axs[1], "a2", "$a_2$")]:
    ax.hist(A["1,2"][key], bins=bins, color=WARM, alpha=0.75, label="lags 1, 2 (as first built)", zorder=3)
    ax.hist(A["12,24"][key], bins=bins, color=GREEN, alpha=0.6, label="lags $n_{Tx}$, $2n_{Tx}$", zorder=3)
    ax.axvline(0, color="0.3", lw=0.6)
    ax.set_xlabel("fitted coefficient " + title)
axs[0].set_ylabel("coefficient sets\n(50 frames, 4 RX, I and Q)")
h, l = axs[0].get_legend_handles_labels()
fig.legend(h, l, fontsize=7, frameon=False, loc="upper center", ncol=2)
fig.tight_layout(pad=0.4, rect=(0, 0, 1, 0.9)); fig.savefig("fig_lpccoef.pdf")
print("done")
