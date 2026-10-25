"""Render each poster equation line as its own tight PNG (300 dpi, fontsize 30 pt).
build_poster.py scales them all by the same factor, so they share one font size."""
import os, json
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from PIL import Image
plt.rcParams.update({'mathtext.fontset': 'stix', 'font.family': 'STIXGeneral'})
os.makedirs('eq', exist_ok=True)
FS = 30
EQ = {
    'c1': r'$e_m = x_m - \hat{x}_m$',
    'c2': r'$\mathrm{bits}(e_m) = \ell(S_4) + S_4,\quad S_4 = \lfloor \log_2 |e_m| \rfloor + 1$',
    'd0': r'$\hat{x}_m = \hat{A}_m\,e^{\,j\hat{\phi}_m}$',
    'd1': r'$\hat{A}_m = \alpha\,\hat{A}_{m-L} + (1-\alpha)\,A_{m-L}$',
    'd2': r'$\hat{\phi}_m = \beta\,\hat{\phi}_{m-L} + (2-\beta)\,\phi_{m-L} - \phi_{m-2L}$',
    'd3': r'$\hat{x}_m = \hat{A}_m\,e^{\,j\hat{\phi}_m},\quad \alpha = 0.6,\ \beta = 0.4$',
    'l1': r'$\hat{x}_m = a_1\,x_{m-L} + a_2\,x_{m-2L}$',
    'l2': r'$R_k = \sum_{m=0}^{N-1} x_m\,x_{m-kL}$',
    'l3': r'$a_1 = \dfrac{R_1(R_0 - R_2)}{R_0^2 - R_1^2},\quad a_2 = \dfrac{R_0R_2 - R_1^2}{R_0^2 - R_1^2}$',
    'cr': r'$\mathrm{CR} = \dfrac{\mathrm{input\ bits}}{\mathrm{compressed\ bits}}$',
}
sizes = {}
for k, t in EQ.items():
    fig = plt.figure(figsize=(14, 3))
    fig.text(0.02, 0.5, t, fontsize=FS, va='center', ha='left')
    fig.savefig(f'eq/{k}.png', dpi=300, transparent=True, bbox_inches='tight', pad_inches=0.02)
    plt.close(fig)
    im = Image.open(f'eq/{k}.png')
    sizes[k] = [im.width / 300, im.height / 300]
json.dump({'fs': FS, 'sizes': sizes}, open('eq/sizes.json', 'w'), indent=1)
for k, v in sizes.items():
    print(k, '%.2f x %.2f in' % tuple(v))
