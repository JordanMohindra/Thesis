"""Dictionary re-derived on frames 0-4 and tested on held-out frames 5-49.
Every one of the 16 categories keeps a codeword (a pseudo-count of 1 is added
to each training count), so the code stays lossless on any input."""
import numpy as np, json
from indep import *
from idealdict import huff_len
Rs, Is = load_stim()
def counts(f):
    R, I = Rs[f], Is[f]; S = {}
    S['nopred'] = np.concatenate([R.ravel(), I.ravel()])
    a, b = drhe_res(R, I, 1);  S['drhe1'] = np.concatenate([a.ravel(), b.ravel()])
    a, b = drhe_res(R, I, 12); S['drhe12'] = np.concatenate([a.ravel(), b.ravel()])
    l = []; l2 = []
    for c in range(4):
        for X in (R[:, :, c], I[:, :, c]):
            l.append(lpc_res(X, 1, 2)[0].ravel()); l2.append(lpc_res(X, 12, 24)[0].ravel())
    S['lpc12'] = np.concatenate(l); S['lpc1224'] = np.concatenate(l2)
    return {k: np.bincount(s4(v), minlength=16) for k, v in S.items()}
H = [counts(f) for f in range(50)]
inb = 128 * 192 * 4 * 32; coef = 32768
pad = lambda b: np.ceil(b / 256) * 256
out = {}
for k in ['nopred', 'drhe1', 'drhe12', 'lpc12', 'lpc1224']:
    L = huff_len(sum(H[f][k] for f in range(5)) + 1)
    assert abs(sum(2.0 ** -L) - 1) < 1e-12 and (L > 0).all()
    side = coef if 'lpc' in k else 0
    cr = lambda f, LL: inb / pad((H[f][k] * (LL + np.arange(16))).sum() + side)
    out[k] = dict(L=L.astype(int).tolist(),
                  cr50=float(np.mean([cr(f, L) for f in range(50)])),
                  cr_test45=float(np.mean([cr(f, L) for f in range(5, 50)])),
                  kiem_test45=float(np.mean([cr(f, HL) for f in range(5, 50)])))
    print(k, out[k]['L'], round(out[k]['kiem_test45'], 4), round(out[k]['cr_test45'], 4))
old = json.load(open('retrain_complete.json'))
print('matches stored retrain_complete.json:',
      all(old[k]['L'] == out[k]['L'] and abs(old[k]['cr_test45'] - out[k]['cr_test45']) < 1e-9 for k in out))
json.dump(out, open('retrain_complete_rerun.json', 'w'), indent=1)
