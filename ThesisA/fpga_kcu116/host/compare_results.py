"""compare_results.py - check a board run against the C-simulation golden output.

    python compare_results.py <drhe|lpc>

Reads  ../results/<algo>/results.bin, comp_<f>.bin   (from run_board.tcl)
       ../golden/golden_<algo>_tdm_compressed.bin    (from hls/export_ips.bat)
Checks, per frame:
  * the frame decompressed ON THE PC (pc_decompress.bat -> pc_decompress.txt)
    equals the original exactly (maxdiff 0). This is the end-to-end test:
    FPGA compresses, PC decompresses.
  * (older builds with an on-chip decompressor: its max_diff must be 0)
  * the compressed size equals the C-simulation size  (=> identical CR)
  * for the dumped frames, the compressed bitstream is byte-identical
Prints per-frame CR, cycle counts, end-to-end latency (last input word read
-> last output word written, Kiem's definition; firmware since Oct 7) and the mean CR (same metric as HLS csim:
input bits / (256-bit words * 256), averaged over frames).
"""
import os, sys, struct

algo = sys.argv[1] if len(sys.argv) > 1 else "drhe"
root = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
rdir = os.path.join(root, "results", algo)
FRAME_BYTES = 128 * 192 * 4 * 4
ERR = {0x01: "comp timeout", 0x02: "decomp timeout", 0x04: "dma_c error", 0x08: "dma_d error",
       0x10: "recon length", 0x20: "decomp left words unread"}

info = {}
ip = os.path.join(rdir, "run_info.txt")
if os.path.exists(ip):
    for line in open(ip):
        k, _, v = line.strip().partition(" ")
        info[k] = v
has_decomp = info.get("decomp", "1") == "1"
pcd = {}
pp = os.path.join(rdir, "pc_decompress.txt")
if os.path.exists(pp):
    for line in open(pp):
        f_, nb_, md_, nm_ = (int(x) for x in line.split())
        pcd[f_] = (md_, nm_)
else:
    print("(no pc_decompress.txt - run pc_decompress.bat %s to decompress on the PC)" % algo)
raw = open(os.path.join(rdir, "results.bin"), "rb").read()
recs = [struct.unpack_from("<8I", raw, 32 * i) for i in range(len(raw) // 32)]

golden = []
gpath = os.path.join(root, "golden", f"golden_{algo}_tdm_compressed.bin")
if os.path.exists(gpath):
    g = open(gpath, "rb").read()
    nF = struct.unpack_from("<I", g, 0)[0]; off = 4
    for _ in range(nF):
        nw = struct.unpack_from("<I", g, off)[0]; off += 4
        golden.append(g[off:off + 32 * nw]); off += 32 * nw
else:
    print(f"(no golden file at {gpath}; only on-board checks will be reported)")

print(f"{'frame':>5} {'bytes':>9} {'CR':>8} {'golden CR':>10} {'comp cyc':>9} {'latency':>8} {'decomp cyc':>10} {'maxdiff':>7}  check")
print("      (maxdiff = after decompression on the PC)" if not has_decomp else "")
ok_all = True; crs = []; gcrs = []
OLD_MARK = 0x5EC0DE00      # older firmware wrote this instead of the latency
def lat_of(r):
    return None if r[7] == OLD_MARK else r[7]
for (f, nbytes, cc, dc, maxd, nmis, st, lat) in recs:
    lat = None if lat == OLD_MARK else lat
    cr = FRAME_BYTES / nbytes if nbytes else 0.0
    notes = []
    if st:
        notes.append(", ".join(v for k, v in ERR.items() if st & k))
    if has_decomp and (maxd or nmis):
        notes.append(f"{nmis} values differ")
    gcr = ""
    if f < len(golden):
        gb = len(golden[f])
        gcr = f"{FRAME_BYTES / gb:10.5f}"; gcrs.append(FRAME_BYTES / gb)
        if nbytes != gb:
            notes.append(f"size {nbytes} != golden {gb}")
        dump = os.path.join(rdir, f"comp_{f}.bin")
        if os.path.exists(dump):
            d = open(dump, "rb").read()[:nbytes]
            if d == golden[f][:nbytes] and nbytes == gb:
                notes.append("bitstream identical")
            else:
                first = next(i for i in range(min(len(d), gb)) if d[i] != golden[f][i]) if len(d) else 0
                notes.append(f"BITSTREAM DIFFERS at byte {first}")
        elif not has_decomp:
            notes.append("NOT DUMPED")
    if not has_decomp:
        if f in pcd:
            notes.append("PC decompress: " + ("exact" if pcd[f][0] == 0 else f"DIFF maxdiff {pcd[f][0]}"))
        else:
            notes.append("NOT DECOMPRESSED ON PC")
    bad = bool(st or (has_decomp and (maxd or nmis)) or
               any(k in n for n in notes for k in ("!=", "DIFFERS", "NOT DUMPED", "DIFF maxdiff", "NOT DECOMPRESSED")))
    ok_all &= not bad
    crs.append(cr)
    print(f"{f:5d} {nbytes:9d} {cr:8.5f} {gcr:>10} {cc:9d} {lat if lat is not None else '-':>8} {dc if has_decomp else 'n/a':>10} {maxd if has_decomp else (pcd[f][0] if f in pcd else '-'):>7}  "
          + ("FAIL: " if bad else "ok  ") + ("; ".join(notes) if notes else ""))

n = len(recs)
print(f"\nframes: {n}")
print(f"mean per-frame CR (board) : {sum(crs) / n:.5f}")
if gcrs:
    print(f"mean per-frame CR (csim)  : {sum(gcrs) / len(gcrs):.5f}   over {len(gcrs)} frames")
cyc = [r[2] for r in recs if r[2]]
if cyc:
    print(f"compress cycles/frame     : min {min(cyc)}  mean {sum(cyc) / len(cyc):.0f}  max {max(cyc)}  (100 MHz)")
    bps = FRAME_BYTES * 8 / (sum(cyc) / len(cyc) / 100e6)
    print(f"compressor throughput     : {bps / 1e9:.2f} Gbit/s input  (= {bps / 2**30:.2f} Gibit/s, the unit Kiem's 11.92 uses)")
    print(f"time per frame            : {sum(cyc) / len(cyc) / 100:.1f} us  -> {100e6 / (sum(cyc) / len(cyc)):.0f} frames/s")
lats = [lat_of(r) for r in recs if lat_of(r) is not None]
if lats:
    print(f"end-to-end latency        : min {min(lats)}  mean {sum(lats) / len(lats):.0f}  max {max(lats)} cycles"
          f"  = {sum(lats) / len(lats) / 100:.2f} us mean  (last input read -> last output written)")
dcyc = [r[3] for r in recs if r[3]] if has_decomp else []
if dcyc:
    print(f"decompress cycles/frame   : min {min(dcyc)}  mean {sum(dcyc) / len(dcyc):.0f}  max {max(dcyc)}")
if has_decomp:
    print("\nRESULT:", "PASS - lossless on every frame and identical to C simulation" if ok_all else "FAIL - see the rows marked FAIL")
else:
    print("\nRESULT:", "PASS - FPGA compressed, PC decompressed: every frame exact, bitstreams identical to C simulation" if ok_all else "FAIL - see the rows marked FAIL")
sys.exit(0 if ok_all else 1)
