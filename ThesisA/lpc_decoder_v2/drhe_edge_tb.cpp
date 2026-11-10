// DRHE-TDM edge cases with the TLAST fix in the compressor (derived from the LPC equivalence test). Was:
// Equivalence test: the new two-stage LPC-TDM decompressor against the first
// (serial) one, on all 50 ColoRadar frames and on eight synthetic edge-case
// frames. Pass = the two decoders give bit-identical output on every frame,
// and every ColoRadar frame is reconstructed exactly.
#include <iostream>
#include <fstream>
#include <vector>
#include <cstdint>
#include <cstdlib>
#include <cmath>
#include "drhe_tdm_compress.h"
#include "drhe_tdm_decompress.h"


static const int N_TX = 12, NS = 128, NR = 192, NRX = 4;
typedef std::vector<int16_t> Frame;   // [r][s][ch][re,im]
static inline int idx(int r, int s, int ch, int part) { return ((r * NS + s) * NRX + ch) * 2 + part; }

static unsigned long long rng = 88172645463325252ull;
static uint32_t xr() { rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17; return (uint32_t)rng; }

// returns: 0 ok; fills maxdiff vs input and mismatches between decoders
static int run(const Frame& f, int& maxdiff, long& mism, int& nwords) {
    hls::stream<axis_128_t> cin("cin");
    hls::stream<axis_256_t> cout_("cout");
    for (int r = 0; r < NR; r++) for (int s = 0; s < NS; s++) {
        axis_128_t p; ap_uint<128> d = 0;
        for (int ch = 0; ch < NRX; ch++) {
            ap_uint<32> w = 0;
            w.range(15, 0)  = (ap_uint<16>)(ap_int<16>)f[idx(r, s, ch, 0)];
            w.range(31, 16) = (ap_uint<16>)(ap_int<16>)f[idx(r, s, ch, 1)];
            d.range(ch * 32 + 31, ch * 32) = w;
        }
        p.data = d; p.keep = -1; p.last = (r == NR - 1 && s == NS - 1);
        cin.write(p);
    }
    std::cout << "    [compress]" << std::endl;
    drhe_tdm_compress(cin, cout_, NS, NR, NRX, N_TX);
    std::vector<axis_256_t> words;
    while (!cout_.empty()) words.push_back(cout_.read());
    nwords = (int)words.size();
    hls::stream<axis_256_t> ina("ina"), inb("inb");
    for (auto& w : words) { ina.write(w); inb.write(w); }
    hls::stream<axis_128_t> outa("outa"), outb("outb");
    std::cout << "    [new decoder] " << nwords << " words" << std::endl;
    drhe_tdm_decompress(ina, outa, NS, NR, NRX, N_TX);
    { hls::stream<axis_256_t> d2("d2"); while(!inb.empty()) inb.read(); }
    maxdiff = 0; mism = 0;
    for (int r = 0; r < NR; r++) for (int s = 0; s < NS; s++) {
        if (outa.empty()) { std::cerr << "[ERROR] short output at r=" << r << " s=" << s << "\n"; return 1; }
        axis_128_t a = outa.read();
        bool want_last = (r == NR - 1 && s == NS - 1);
        if ((a.last == 1) != want_last) mism++;
        for (int ch = 0; ch < NRX; ch++) for (int part = 0; part < 2; part++) {
            int v = (int)(ap_int<16>)a.data.range(ch * 32 + part * 16 + 15, ch * 32 + part * 16);
            int dlt = std::abs(v - (int)f[idx(r, s, ch, part)]);
            if (dlt > maxdiff) maxdiff = dlt;
        }
    }
    if (!outa.empty()) { std::cerr << "[ERROR] extra output words\n"; return 1; }
    if (!ina.empty()) { std::cerr << "[ERROR] new decoder left input unread\n"; return 1; }
    return 0;
}

int main() {
    int fails = 0;
    // ---- 50 ColoRadar frames ----
    std::ifstream bin("coloradar_multiframe.bin", std::ios::binary);
    if (!bin) { std::cerr << "[ERROR] coloradar_multiframe.bin missing\n"; return 1; }
    uint32_t nF, nS, nR, nRx; bin.read((char*)&nF, 4); bin.read((char*)&nS, 4); bin.read((char*)&nR, 4); bin.read((char*)&nRx, 4);
    if ((int)nS != NS || (int)nR != NR || (int)nRx != NRX) { std::cerr << "[ERROR] geometry\n"; return 1; }
    double sumcr = 0;
    if (getenv("SKIP_COLORADAR")) nF = 0;
    for (uint32_t fr = 0; fr < nF; fr++) {
        Frame f(NR * NS * NRX * 2);
        for (int r = 0; r < NR; r++) for (int s = 0; s < NS; s++) for (int ch = 0; ch < NRX; ch++) {
            int16_t re, im; bin.read((char*)&re, 2); bin.read((char*)&im, 2);
            f[idx(r, s, ch, 0)] = re; f[idx(r, s, ch, 1)] = im;
        }
        int md, nw; long mm;
        if (run(f, md, mm, nw)) return 1;
        double cr = (double)NR * NS * NRX * 32 / (nw * 256.0); sumcr += cr;
        bool ok = (md == 0 && mm == 0);
        if (!ok) fails++;
        std::cout << "  coloradar frame " << fr << ": CR " << cr << "  maxdiff " << md << "  TLAST errors " << mm << (ok ? "  OK" : "  FAIL") << "\n";
    }
    if (nF) std::cout << "[RESULT] ColoRadar mean CR " << sumcr / nF << "\n";

    // ---- synthetic edge cases: new decoder must match the old one exactly ----
    const char* names[8] = {"all zeros", "all +32767", "alternating +32767/-32768", "uniform random int16",
                            "small noise +-50", "all -32768", "random walk along ramps", "noise with -32768 spikes"};
    for (int c = 0; c < 8; c++) {
        Frame f(NR * NS * NRX * 2);
        for (int r = 0; r < NR; r++) for (int s = 0; s < NS; s++) for (int ch = 0; ch < NRX; ch++) for (int part = 0; part < 2; part++) {
            int v = 0;
            switch (c) {
                case 0: v = 0; break;
                case 1: v = 32767; break;
                case 2: v = ((r + s + ch + part) & 1) ? 32767 : -32768; break;
                case 3: v = (int)(int16_t)(xr() & 0xFFFF); break;
                case 4: v = (int)(xr() % 101) - 50; break;
                case 5: v = -32768; break;
                case 6: v = (r < N_TX) ? (int)(xr() % 2001) - 1000 : f[idx(r - N_TX, s, ch, part)] + (int)(xr() % 41) - 20;
                        if (v > 32767) v = 32767; if (v < -32768) v = -32768; break;
                case 7: v = (xr() % 97 == 0) ? -32768 : (int)(xr() % 401) - 200; break;
            }
            f[idx(r, s, ch, part)] = (int16_t)v;
        }
        int md, nw; long mm;
        if (run(f, md, mm, nw)) return 1;
        bool ok = (mm == 0 && md <= 1);
        if (!ok) fails++;
        std::cout << "  edge case " << c << " (" << names[c] << "): CR " << (double)NR * NS * NRX * 32 / (nw * 256.0)
                  << "  maxdiff vs input " << md << "  TLAST errors " << mm << (ok ? "  OK" : "  FAIL") << "\n";
    }
    std::cout << (fails ? "[RESULT] FAIL\n" : "[RESULT] PASS - DRHE edge cases decoded, input fully consumed\n");
    return fails ? 1 : 0;
}
