import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

plt.rcParams.update({"font.size": 9, "font.family": "serif",
                     "axes.grid": True, "grid.alpha": 0.25, "grid.linewidth": 0.5,
                     "axes.spines.top": False, "axes.spines.right": False})
WARM="#B5553F"; GREEN="#2F6D4F"; SLATE="#8A8F98"
HL=[4,3,2,2,2,5,6,7,8,9,10,11,14,14,13,12]

m   = np.arange(168,184)
d1  = np.array([-136, 23,-22,-70,-53, 14, 65, 63, 24, -8, -1, 56,-143, 25,-22,-72])
d12 = np.array([   3, -3,  0, -1,  1,  3, -4,  3, -1, -2, -1,  0,  -2,  4, -1,  1])
b1  = np.array([16,10,10,14,12, 6,14,12,10, 6, 4,12,16,10,10,14])
b12 = np.array([ 4, 4, 4, 4, 4, 4, 5, 4, 4, 4, 4, 4, 4, 5, 4, 4])

fig, (axA, axB) = plt.subplots(2,1, figsize=(6.2,4.8),
                               gridspec_kw={"height_ratios":[1.45,1.0], "hspace":0.40})

# ---------- Panel A: |residual| with S4 category bands ----------
for k in range(1,9):
    lo = 2**(k-1)
    if k % 2 == 0:
        axA.axhspan(lo, lo*2, color="0.5", alpha=0.07, zorder=0)
    axA.text(184.6, lo*1.40, f"$S_4\\!=\\!{k}$   {HL[k]+k} bits",
             fontsize=6.6, va="center", color="0.38")
axA.set_yscale("log", base=2)
axA.set_ylim(0.55, 800)
axA.set_xlim(167.2, 184.3)

def plot_series(ax, v, col, lab, mk):
    a = np.abs(v).astype(float)
    zero = a == 0
    a[zero] = 0.62                      # park exact zeros on the floor
    ax.plot(m, a, color=col, marker=mk, ms=4, lw=1.1, label=lab, zorder=3)
    if zero.any():
        ax.plot(m[zero], a[zero], marker=mk, ms=4, lw=0, color=col,
                markerfacecolor="white", zorder=4)

plot_series(axA, d1,  WARM,  "lag 1 (adjacent ramp, other transmitter)", "o")
plot_series(axA, d12, GREEN, "lag $n_{\\mathrm{Tx}}$ (same transmitter)", "s")
axA.axhline(0.62, color="0.6", lw=0.5, ls=":")
axA.text(184.3, 0.62, "  $S_4\\!=\\!0$   4 bits", fontsize=6.6, va="center", color="0.38")

axA.set_ylabel("$|$residual$|$")
axA.set_xticks(m[::3])
axA.set_yticks([1,2,4,8,16,32,64,128,256])
axA.set_yticklabels(["1","2","4","8","16","32","64","128","256"])
axA.legend(fontsize=7, frameon=False, loc="upper center", ncol=2, bbox_to_anchor=(0.46,1.02),
           columnspacing=1.3, handlelength=1.6)
axA.set_title("The same 16 samples, predicted two ways", fontsize=9)

# ---------- Panel B: bit cost per sample ----------
w=0.38
axB.bar(m-w/2, b1,  width=w, color=WARM,  zorder=3, label=f"lag 1: {b1.sum()} bits total")
axB.bar(m+w/2, b12, width=w, color=GREEN, zorder=3, label=f"lag $n_{{\\mathrm{{Tx}}}}$: {b12.sum()} bits total")
axB.axhline(16, color="0.35", ls="--", lw=0.9, zorder=4)
axB.text(184.2, 16.4, "16 bits = uncompressed", fontsize=6.6, color="0.35", ha="right")
axB.set_ylim(0,23.5); axB.set_xlim(167.2,184.3)
axB.set_xticks(m[::3])
axB.set_xlabel("ramp index $m$")
axB.set_ylabel("bits to code")
axB.legend(fontsize=7, frameon=False, loc="upper left", ncol=2, bbox_to_anchor=(0.0,1.04),
           columnspacing=1.3, handlelength=1.6)

fig.subplots_adjust(left=0.11, right=0.845, top=0.93, bottom=0.10)
fig.savefig("fig_worked.pdf")

print("ok")
