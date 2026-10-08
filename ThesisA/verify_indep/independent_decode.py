"""independent_decode.py - an independent Python decoder for the DRHE / LPC
(TDM, lag nTx) bitstreams, written from the format description only.

Result on the 50 C-simulation (golden) frames:
  * LPC  : every frame reconstructed exactly (fixed-point predictor).
  * DRHE : 42 frames exact, 8 frames off by 1-6 LSB on a handful of samples.
    The DRHE predictor uses float sqrt/atan2/sin/cos; this file uses double
    precision NumPy, and a prediction that rounds differently by one LSB then
    propagates along that (transmitter, range bin) chain. A DRHE decoder must
    reproduce the encoder's float arithmetic bit for bit, which is why the
    board flow decompresses with the HLS C++ itself (fpga_kcu116/host/
    pc_decompress.bat). A fixed-point predictor, as in Kiem's design, is far
    easier to reproduce exactly on another machine.

    python independent_decode.py <drhe|lpc> <compressed_frame.bin> [-o frame.bin]

As a module:
    frame = decompress(algo, data)     # -> int16 array [ramp, bin, rx, 2]
                                       #    (same layout as frames_N.bin)

Bitstream (see thesis Appendix B): 256-bit words, little-endian, bits used
LSB first. LPC starts with a coefficient table (per RX, per range bin:
a1_re, a2_re, a1_im, a2_im as 16-bit two's complement, a1 = q/2^14,
a2 = q/2^15). Then, in raster order (ramp, bin, rx), one residual for the real
and one for the imaginary part: a Huffman code for the S4 category followed by
S4 APPEND bits. The predictors are the closed-loop TDM predictors of the HLS
cores (DRHE: Kiem's magnitude/phase filters at lag nTx; LPC: order-2 at lags
nTx and 2 nTx), so reconstruction is exact.
"""
import sys
import numpy as np

N_SAMPLES, N_RAMPS, N_RX, N_TX = 128, 192, 4, 12

# Kiem's fixed dictionary (Appendix A), stored LSB-first (code, length) for S4 = 0..15
KIEM_CODES = [(0x0005, 4), (0x0001, 3), (0x0002, 2), (0x0000, 2), (0x0003, 2), (0x000D, 5),
              (0x001D, 6), (0x003D, 7), (0x007D, 8), (0x00FD, 9), (0x01FD, 10), (0x03FD, 11),
              (0x3FFD, 14), (0x1FFD, 14), (0x0FFD, 13), (0x07FD, 12)]
# The TDM cores use the re-derived dictionaries (thesis report; code lengths in
# retrain_complete.json "drhe12" and "lpc1224"), canonical codes stored LSB-first.
CODES = {"drhe": [(0x0003,3),(0x0001,2),(0x0000,1),(0x0007,4),(0x000F,5),(0x001F,6),(0x003F,7),(0x007F,8),(0x00FF,9),(0x01FF,10),(0x03FF,11),(0x1FFF,14),(0x3FFF,14),(0x07FF,13),(0x17FF,13),(0x0FFF,13)],
         "lpc": [(0x0003,3),(0x0000,1),(0x0001,2),(0x0007,4),(0x000F,5),(0x001F,6),(0x003F,7),(0x007F,8),(0x00FF,9),(0x01FF,10),(0x07FF,13),(0x17FF,13),(0x0FFF,13),(0x1FFF,13),(0x03FF,12),(0x0BFF,12)]}
# lookup by the low 14 bits of the stream: each code set is prefix-free, so the
# first code (in any order) whose bits match is the only match
def _make_lut(codes):
    s4 = np.full(1 << 14, -1, dtype=np.int8); ln = np.zeros(1 << 14, dtype=np.int8)
    for s, (c, l) in enumerate(codes):
        for hi in range(1 << (14 - l)):
            s4[(hi << l) | c] = s; ln[(hi << l) | c] = l
    assert (s4 >= 0).all()
    return s4, ln
_LUTS = {a: _make_lut(c) for a, c in CODES.items()}
_LUTS["kiem"] = _make_lut(KIEM_CODES)


def mround(x):
    """round half away from zero (MATLAB / HLS behaviour)"""
    return np.sign(x) * np.floor(np.abs(x) + 0.5)


def wrap16(v):
    return np.mod(v + 32768, 65536) - 32768


class BitReader:
    def __init__(self, data, algo="drhe"):
        self.lut_s4, self.lut_len = _LUTS[algo]
        self.v = int.from_bytes(bytes(data), "little")
        self.p = 0
        self.nbits = 8 * len(data)

    def take(self, n):
        x = (self.v >> self.p) & ((1 << n) - 1)
        self.p += n
        return x

    def residual(self):
        w = (self.v >> self.p) & 0x3FFF
        s = int(self.lut_s4[w]); self.p += int(self.lut_len[w])
        if s == 0:
            return 0
        a = self.take(s)
        return a if a >> (s - 1) else a - (1 << s) + 1      # inverse of APPEND


def _residuals(br):
    """[ramp, bin, rx] residual arrays for the real and imaginary parts"""
    dr = np.empty((N_RAMPS, N_SAMPLES, N_RX)); di = np.empty_like(dr)
    for r in range(N_RAMPS):
        for s in range(N_SAMPLES):
            for c in range(N_RX):
                dr[r, s, c] = br.residual()
                di[r, s, c] = br.residual()
    return dr, di


def _drhe(dr, di):
    out_r = np.empty_like(dr); out_i = np.empty_like(di)
    a, b = 0.6, 0.4
    for off in range(N_TX):                          # one predictor state per transmitter
        z = np.zeros((N_SAMPLES, N_RX))
        mp_, m_, pp_, p1, p2 = z.copy(), z.copy(), z.copy(), z.copy(), z.copy()
        for m in range(off, N_RAMPS, N_TX):
            mp = a * mp_ + (1 - a) * m_
            ph = b * pp_ + (2 - b) * p1 - p2
            ph = np.where(ph > np.pi, ph - 2 * np.pi, np.where(ph < -np.pi, ph + 2 * np.pi, ph))
            pre = mround(mp * np.cos(ph)); pim = mround(mp * np.sin(ph))
            rr = wrap16(dr[m] + pre); ri = wrap16(di[m] + pim)
            out_r[m] = rr; out_i[m] = ri
            cm = np.sqrt(rr ** 2 + ri ** 2); cp = np.arctan2(ri, rr + 0.0)
            p2 = p1; p1 = cp; pp_ = ph; m_ = cm; mp_ = mp
    return out_r, out_i


def _lpc_coefs(br):
    def s16(q):
        return q - 65536 if q >= 32768 else q
    co = np.empty((N_RX, N_SAMPLES, 4))
    for c in range(N_RX):
        for n in range(N_SAMPLES):
            a1r, a2r, a1i, a2i = (s16(br.take(16)) for _ in range(4))
            co[c, n] = (a1r / 2 ** 14, a2r / 2 ** 15, a1i / 2 ** 14, a2i / 2 ** 15)
    return co


def _lpc(dr, di, co):
    out_r = np.zeros_like(dr); out_i = np.zeros_like(di)
    a1r, a2r = co[:, :, 0].T, co[:, :, 1].T          # [bin, rx]
    a1i, a2i = co[:, :, 2].T, co[:, :, 3].T
    for m in range(N_RAMPS):
        q1r = out_r[m - N_TX] if m >= N_TX else 0.0
        q2r = out_r[m - 2 * N_TX] if m >= 2 * N_TX else 0.0
        q1i = out_i[m - N_TX] if m >= N_TX else 0.0
        q2i = out_i[m - 2 * N_TX] if m >= 2 * N_TX else 0.0
        out_r[m] = wrap16(dr[m] + mround(a1r * q1r + a2r * q2r))
        out_i[m] = wrap16(di[m] + mround(a1i * q1i + a2i * q2i))
    return out_r, out_i


def decompress(algo, data):
    br = BitReader(data, algo)
    co = _lpc_coefs(br) if algo == "lpc" else None
    dr, di = _residuals(br)
    if br.p > br.nbits:
        raise ValueError(f"bitstream too short: needed {br.p} bits, have {br.nbits}")
    rr, ri = _drhe(dr, di) if algo == "drhe" else _lpc(dr, di, co)
    return np.stack([rr, ri], axis=-1).astype(np.int16)      # [ramp, bin, rx, re/im]


if __name__ == "__main__":
    if len(sys.argv) < 3 or sys.argv[1] not in ("drhe", "lpc"):
        sys.exit(__doc__)
    algo, src = sys.argv[1], sys.argv[2]
    dst = sys.argv[sys.argv.index("-o") + 1] if "-o" in sys.argv else src.rsplit(".", 1)[0] + "_decompressed.bin"
    frame = decompress(algo, open(src, "rb").read())
    frame.tofile(dst)
    print(f"{src} -> {dst}  ({frame.nbytes} bytes, layout [ramp][bin][rx][re,im] int16)")
