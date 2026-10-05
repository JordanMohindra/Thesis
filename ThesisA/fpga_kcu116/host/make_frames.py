"""make_frames.py - strip the 16-byte header from coloradar_multiframe.bin.

    python make_frames.py <path/to/coloradar_multiframe.bin> [nframes=50]

Writes ../out/frames_<n>.bin: n frames back to back, 393,216 bytes each, in
exactly the layout the compressor's 128-bit input word expects (per sample:
RX0 re, RX0 im, ..., RX3 im, int16 little-endian). xsdb loads this file
straight into DDR.
"""
import os, sys, struct

src = sys.argv[1] if len(sys.argv) > 1 else os.path.join("..", "..", "hls_component", "coloradar_multiframe.bin")
n_req = int(sys.argv[2]) if len(sys.argv) > 2 else 50
with open(src, "rb") as fh:
    nF, nS, nR, nRx = struct.unpack("<4I", fh.read(16))
    assert (nS, nR, nRx) == (128, 192, 4), f"unexpected geometry {nS}x{nR}x{nRx}"
    n = min(n_req, nF)
    frame_bytes = nS * nR * nRx * 4
    data = fh.read(n * frame_bytes)
assert len(data) == n * frame_bytes, "file shorter than its header says"
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out", f"frames_{n}.bin")
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, "wb") as fh:
    fh.write(data)
print(f"{n} frames x {frame_bytes} bytes -> {os.path.normpath(out)}")
