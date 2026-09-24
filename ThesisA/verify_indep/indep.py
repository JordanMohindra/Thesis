"""
Independent re-implementation (Python/NumPy) of the whole ColoRadar compression
chain, written from the thesis text and NOT sharing code with Matlab_Sim or the
HLS sources. Used to re-verify every compression number in the report.

Step A: raw ColoRadar frame -> FX16 range-FFT codes, compared with the HLS
        stimulus file coloradar_multiframe.bin (what MATLAB exported).
Step B: from the stimulus file, bit counts for
        no prediction, DRHE lag 1, DRHE lag 12, LPC lags 1,2, LPC lags 12,24
        (HLS-style: 16-bit quantised coefficients, closed loop, 256-bit padding).
"""
import numpy as np, sys, json, os

# Folder holding frame_0.bin ... frame_49.bin (raw ColoRadar frames) and
# coloradar_multiframe.bin (the HLS stimulus). Override with COLORADAR_RAW.
RAW = os.environ.get('COLORADAR_RAW', os.path.join(os.path.dirname(os.path.abspath(__file__)), 'raw'))
NS, NC, NR, NT = 256, 16, 16, 12
HL = np.array([4, 3, 2, 2, 2, 5, 6, 7, 8, 9, 10, 11, 14, 14, 13, 12])


def mround(x):
    """MATLAB round: half away from zero."""
    return np.sign(x) * np.floor(np.abs(x) + 0.5)


def load_raw(f):
    a = np.fromfile(f'{RAW}/frame_{f}.bin', dtype='<i2').astype(np.float64)
    z = a[0::2] + 1j * a[1::2]
    z = z.reshape(NT, NR, NC, NS)            # [t, r, c, s]
    # ramp = c*NT + t  -> cube[s, ramp, r]
    cube = np.transpose(z, (3, 2, 0, 1)).reshape(NS, NC * NT, NR)
    return cube


def fx16_from_raw(cube):
    cube = cube - cube.mean(axis=0, keepdims=True)          # per-ramp DC removal
    k = np.arange(NS)
    w = 0.5 * (1 - np.cos(2 * np.pi * k / (NS - 1)))         # MATLAB hann (symmetric)
    x = cube * (2.0 ** 16) * w[:, None, None]               # bitWidth 16 -> shift 16
    X = np.fft.fft(x, axis=0) / NS
    X = X[:NS // 2]
    maxfft = 32767 * 2.0 ** 16 * w.sum() / (2 * NS)
    sc = 32767 / maxfft
    re = np.clip(mround(X.real * sc), -32768, 32767)
    im = np.clip(mround(X.imag * sc), -32768, 32767)
    return re, im, cube


def load_stim():
    b = np.fromfile(f'{RAW}/coloradar_multiframe.bin', dtype='<u4', count=4)
    nF, nS, nRmp, nRx = [int(v) for v in b]
    d = np.fromfile(f'{RAW}/coloradar_multiframe.bin', dtype='<i2', offset=16)
    d = d.reshape(nF, nRmp, nS, nRx, 2).astype(np.float64)
    re = np.transpose(d[..., 0], (0, 2, 1, 3))   # [f, bin, ramp, rx]
    im = np.transpose(d[..., 1], (0, 2, 1, 3))
    return re, im


def s4(v):
    a = np.abs(v)
    s = np.zeros(v.shape, dtype=np.int64)
    nz = a > 0
    s[nz] = np.minimum(15, np.floor(np.log2(a[nz])).astype(np.int64) + 1)
    return s


def bits(v):
    s = s4(v)
    return int((HL[s] + s).sum())


def wrap16(v):
    return np.mod(v + 32768, 65536) - 32768


def entropy(v):
    _, c = np.unique(v, return_counts=True)
    p = c / c.sum()
    return float(-(p * np.log2(p)).sum())


def drhe_res(R, I, lag, clamp_closed=True):
    """R, I: [bin, ramp, rx]. Kiem 3.5.3 model; state per transmitter slot."""
    nB, nRm, nRx = R.shape
    dR = np.zeros_like(R); dI = np.zeros_like(I)
    a, b = 0.6, 0.4
    for off in range(lag):
        z = np.zeros((nB, nRx))
        mp_, m_, pp_, p1, p2 = z.copy(), z.copy(), z.copy(), z.copy(), z.copy()
        for m in range(off, nRm, lag):
            re, im = R[:, m, :], I[:, m, :]
            mp = a * mp_ + (1 - a) * m_
            ph = b * pp_ + (2 - b) * p1 - p2
            ph = np.where(ph > np.pi, ph - 2 * np.pi, np.where(ph < -np.pi, ph + 2 * np.pi, ph))
            pre = mround(mp * np.cos(ph)); pim = mround(mp * np.sin(ph))
            d_r = wrap16(re - pre); d_i = wrap16(im - pim)
            if clamp_closed:
                d_r = np.where(d_r == -32768, -32767, d_r)
                d_i = np.where(d_i == -32768, -32767, d_i)
                rr = wrap16(d_r + pre); ri = wrap16(d_i + pim)
            else:
                rr, ri = re, im
            dR[:, m, :] = d_r; dI[:, m, :] = d_i
            cm = np.sqrt(rr ** 2 + ri ** 2); cp = np.arctan2(ri, rr + 0.0)
            p2 = p1; p1 = cp; pp_ = ph; m_ = cm; mp_ = mp
    return dR, dI


def q_a1(x):   # ap_fixed<16,2>, AP_TRN (floor), range [-2, 2)
    return np.clip(np.floor(x * 2 ** 14), -2 ** 15, 2 ** 15 - 1) / 2 ** 14


def q_a2(x):   # ap_fixed<16,1>, AP_TRN, range [-1, 1)
    return np.clip(np.floor(x * 2 ** 15), -2 ** 15, 2 ** 15 - 1) / 2 ** 15


def lpc_res(X, L1, L2, quant=True):
    """X: [bin, ramp] one part of one RX. x_hat[m] = a1 x[m-L1] + a2 x[m-L2]."""
    nB, N = X.shape
    R0 = (X * X).sum(1)
    R1 = (X[:, L1:] * X[:, :N - L1]).sum(1)
    R2 = (X[:, L2:] * X[:, :N - L2]).sum(1)
    det = R0 ** 2 - R1 ** 2
    with np.errstate(divide='ignore', invalid='ignore'):
        a1 = np.where(det != 0, R1 * (R0 - R2) / det, 0.0)
        a2 = np.where(det != 0, (R0 * R2 - R1 ** 2) / det, 0.0)
    bad = (det == 0) | (np.abs(a2) >= 1) | (np.abs(a1) >= (1 - a2))
    a1 = np.where(bad, 0.0, a1); a2 = np.where(bad, 0.0, a2)
    if quant:
        a1 = q_a1(np.float32(a1).astype(np.float64)); a2 = q_a2(np.float32(a2).astype(np.float64))
    X1 = np.concatenate([np.zeros((nB, L1)), X[:, :N - L1]], 1)
    X2 = np.concatenate([np.zeros((nB, L2)), X[:, :N - L2]], 1)
    D = wrap16(X - mround(a1[:, None] * X1 + a2[:, None] * X2))
    return D, int((~bad).sum()), a1, a2


def pad256(b):
    return int(np.ceil(b / 256.0) * 256)


if __name__ == '__main__':
    out = {}
    nF = 50
    Rs, Is = load_stim()
    # ---------------- Step A: raw -> FX16 vs stimulus -----------------
    mism = []; peak_raw = []; peak_fx = []; peak_fx16 = []
    for f in range(nF):
        re, im, cube = fx16_from_raw(load_raw(f))
        d = np.abs(re[:, :, :4] - Rs[f]).max(), np.abs(im[:, :, :4] - Is[f]).max()
        n = int((re[:, :, :4] != Rs[f]).sum() + (im[:, :, :4] != Is[f]).sum())
        mism.append((f, n, float(max(d))))
        peak_raw.append(float(max(np.abs(cube.real).max(), np.abs(cube.imag).max())))
        peak_fx16.append(float(max(np.abs(re).max(), np.abs(im).max())))
        peak_fx.append(float(max(np.abs(Rs[f]).max(), np.abs(Is[f]).max())))
    out['stim_mismatch_values_total'] = sum(m[1] for m in mism)
    out['stim_mismatch_maxabs'] = max(m[2] for m in mism)
    out['stim_values_total'] = int(nF * Rs[0].size * 2)
    out['peak_raw_after_dc_16rx_max'] = max(peak_raw)
    out['peak_raw_after_dc_16rx_frame0'] = peak_raw[0]
    out['peak_fx16_16rx_max'] = max(peak_fx16)
    out['peak_fx16_4rx_max'] = max(peak_fx)
    out['peak_fx16_4rx_first5'] = max(peak_fx[:5])
    print('step A', json.dumps({k: out[k] for k in out}, indent=1)); sys.stdout.flush()

    # ---------------- Step B: bit counts --------------------------------
    names = ['nopred', 'drhe1', 'drhe12', 'lpc12', 'lpc1224', 'drhe1_open']
    per = {k: [] for k in names}
    ent_raw = []; ent_drhe1 = []; stable = [0, 0]; lpc_blocks = []
    s4h = {k: np.zeros(16) for k in ['nopred', 'drhe1', 'drhe12', 'lpc12', 'lpc1224']}
    q99 = {k: [] for k in s4h}
    coef_bits = 128 * 4 * 4 * 16
    for f in range(nF):
        R, I = Rs[f], Is[f]
        nval = R.size * 2
        per['nopred'].append(bits(R) + bits(I))
        d1r, d1i = drhe_res(R, I, 1)
        per['drhe1'].append(bits(d1r) + bits(d1i))
        d1or, d1oi = drhe_res(R, I, 1, clamp_closed=False)
        per['drhe1_open'].append(bits(d1or) + bits(d1oi))
        d12r, d12i = drhe_res(R, I, 12)
        per['drhe12'].append(bits(d12r) + bits(d12i))
        tot12 = 0; tot1224 = 0; ll12 = []; ll1224 = []
        for c in range(4):
            for X in (R[:, :, c], I[:, :, c]):
                D, ns, _, _ = lpc_res(X, 1, 2); tot12 += bits(D); ll12.append(D.ravel())
                stable[0] += ns; stable[1] += X.shape[0]
                D2, _, _, _ = lpc_res(X, 12, 24); tot1224 += bits(D2); ll1224.append(D2.ravel())
        per['lpc12'].append(tot12 + coef_bits)
        per['lpc1224'].append(tot1224 + coef_bits)
        if f < 5:
            ent_raw.append(entropy(np.concatenate([R.ravel(), I.ravel()])))
            ent_drhe1.append(entropy(np.concatenate([d1r.ravel(), d1i.ravel()])))
            sets = {'nopred': np.concatenate([R.ravel(), I.ravel()]),
                    'drhe1': np.concatenate([d1r.ravel(), d1i.ravel()]),
                    'drhe12': np.concatenate([d12r.ravel(), d12i.ravel()]),
                    'lpc12': np.concatenate(ll12), 'lpc1224': np.concatenate(ll1224)}
            for k, v in sets.items():
                s4h[k] += np.bincount(s4(v), minlength=16)
                q99[k].append(float(np.quantile(np.abs(v), 0.99)))
            # LPC per-TX blocks (variant 4)
            b4 = 0
            for t in range(12):
                idx = np.arange(t, 192, 12)
                for c in range(4):
                    for X in (R[:, idx, c], I[:, idx, c]):
                        D, _, _, _ = lpc_res(X, 1, 2, quant=False); b4 += bits(D)
            lpc_blocks.append(b4 + coef_bits * 12)
        if f % 10 == 0:
            print('frame', f, {k: per[k][-1] for k in names}); sys.stdout.flush()
    inb = 128 * 192 * 4 * 32
    res = {}
    for k in names:
        b = np.array(per[k], dtype=float)
        bp = np.array([pad256(x) for x in per[k]], dtype=float)
        res[k] = dict(avgCR_nopad=float(np.mean(inb / b)), avgCR_pad=float(np.mean(inb / bp)),
                      first5_bpv=float(np.mean(b[:5]) / (inb / 16)), frame0_bits=int(b[0]),
                      perframe_pad=[int(x) for x in bp])
    res['lpc_blocks_first5_bpv'] = float(np.mean(lpc_blocks) / (inb / 16))
    res['entropy_raw_first5'] = float(np.mean(ent_raw))
    res['entropy_drhe1_first5'] = float(np.mean(ent_drhe1))
    res['lpc_stable_pct'] = 100 * stable[0] / stable[1]
    res['s4hist_first5_pct'] = {k: (100 * v / v.sum()).round(2).tolist() for k, v in s4h.items()}
    res['q99_first5'] = {k: float(np.mean(v)) for k, v in q99.items()}
    out.update(res)
    json.dump(out, open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'indep_results.json'), 'w'), indent=1)
    for k in names:
        print(k, res[k]['avgCR_nopad'], res[k]['avgCR_pad'], res[k]['first5_bpv'], 16 / res[k]['first5_bpv'])
    print('entropy', res['entropy_raw_first5'], res['entropy_drhe1_first5'], 'stable', res['lpc_stable_pct'])
    print('lpc blocks bpv', res['lpc_blocks_first5_bpv'], 16 / res['lpc_blocks_first5_bpv'])
    print('q99', res['q99_first5'])
    print('s4', res['s4hist_first5_pct'])
