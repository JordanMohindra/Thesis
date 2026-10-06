// ===========================================================================
//  pc_decompress_tb.cpp - the PC-side decompressor for the KCU116 board runs.
//
//  The FPGA only compresses. This program runs the decompressor C++ (the same
//  drhe_tdm_decompress / lpc_tdm_decompress source that was verified lossless
//  in C simulation) on the PC, using the Vitis HLS bit-accurate C models of
//  the floating-point maths. That matters for DRHE: its predictor uses float
//  sqrt/atan2/sin/cos, and the decoder must reproduce the encoder's arithmetic
//  bit for bit. A double-precision re-implementation drifts by a few LSB on 8
//  of the 50 ColoRadar frames.
//
//  Built and run through Vitis C simulation by pc_decompress.bat. Reads the job
//  file named by the environment variable PCD_JOB:
//      line 1: algo (drhe | lpc)
//      line 2: frames file (frames_N.bin: originals, for the comparison)
//      line 3: number of frames
//      line 4: results directory (comp_<f>.bin in, recon_<f>.bin out)
//  Writes recon_<f>.bin (same layout as the frames file) and pc_decompress.txt
//  with one line per frame: frame bytes maxdiff mismatches.
// ===========================================================================
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>
#include <fstream>
#include <iostream>

#ifdef ALGO_LPC
#include "lpc_tdm_decompress.h"
#define DECOMPRESS lpc_tdm_decompress
#else
#include "drhe_tdm_decompress.h"
#define DECOMPRESS drhe_tdm_decompress
#endif

static const int N_SAMPLES = 128, N_RAMPS = 192, N_RX = 4, N_TX = 12;
static const size_t FRAME_BYTES = (size_t)N_SAMPLES * N_RAMPS * N_RX * 4;

static bool read_file(const std::string& p, std::vector<unsigned char>& out) {
    std::ifstream f(p, std::ios::binary);
    if (!f) return false;
    out.assign(std::istreambuf_iterator<char>(f), std::istreambuf_iterator<char>());
    return true;
}

int main() {
    const char* job = std::getenv("PCD_JOB");
    if (!job) { std::cerr << "[ERROR] PCD_JOB not set - run pc_decompress.bat\n"; return 1; }
    std::ifstream jf(job);
    std::string algo, frames_path, nfr, rdir;
    std::getline(jf, algo); std::getline(jf, frames_path); std::getline(jf, nfr); std::getline(jf, rdir);
    int nframes = std::atoi(nfr.c_str());
    std::cout << "[INFO] PC decompression: " << algo << ", " << nframes << " frames from " << rdir << std::endl;

    std::vector<unsigned char> frames;
    if (!read_file(frames_path, frames) || frames.size() < (size_t)nframes * FRAME_BYTES) {
        std::cerr << "[ERROR] cannot read " << frames_path << std::endl; return 1;
    }
    std::ofstream summary(rdir + "/pc_decompress.txt");
    int worst = 0, n_done = 0, n_bad = 0;

    for (int f = 0; f < nframes; f++) {
        std::vector<unsigned char> comp;
        std::string cpath = rdir + "/comp_" + std::to_string(f) + ".bin";
        if (!read_file(cpath, comp) || comp.empty()) { std::cout << "  frame " << f << ": no compressed data, skipped" << std::endl; continue; }
        size_t nwords = (comp.size() + 31) / 32;
        comp.resize(nwords * 32, 0);

        hls::stream<axis_256_t> in("in");
        hls::stream<axis_128_t> out("out");
        for (size_t w = 0; w < nwords; w++) {
            axis_256_t p;
            ap_uint<256> d = 0;
            for (int b = 0; b < 32; b++) d.range(8 * b + 7, 8 * b) = comp[w * 32 + b];
            p.data = d; p.keep = -1; p.strb = -1; p.last = (w + 1 == nwords);
            in.write(p);
        }
        DECOMPRESS(in, out, N_SAMPLES, N_RAMPS, N_RX, N_TX);

        std::vector<unsigned char> rec(FRAME_BYTES);
        size_t o = 0;
        bool short_out = false;
        for (int r = 0; r < N_RAMPS && !short_out; r++)
            for (int s = 0; s < N_SAMPLES; s++) {
                if (out.empty()) { short_out = true; break; }
                ap_uint<128> d = out.read().data;
                for (int b = 0; b < 16; b++) rec[o++] = (unsigned char)d.range(8 * b + 7, 8 * b);
            }
        std::ofstream(rdir + "/recon_" + std::to_string(f) + ".bin", std::ios::binary)
            .write(reinterpret_cast<const char*>(rec.data()), rec.size());

        const unsigned char* orig = frames.data() + (size_t)f * FRAME_BYTES;
        int maxd = 0; long nmis = 0;
        for (size_t i = 0; i < FRAME_BYTES; i += 2) {
            int16_t a, b; std::memcpy(&a, orig + i, 2); std::memcpy(&b, rec.data() + i, 2);
            int d = std::abs((int)a - (int)b);
            if (d) { nmis++; if (d > maxd) maxd = d; }
        }
        if (short_out) { maxd = 65535; }
        std::cout << "  frame " << f << ": " << comp.size() << " compressed bytes, maxdiff " << maxd
                  << ", mismatches " << nmis << (maxd ? "  DIFF" : "  OK") << std::endl;
        summary << f << " " << comp.size() << " " << maxd << " " << nmis << "\n";
        if (maxd > worst) worst = maxd;
        if (maxd) n_bad++;
        n_done++;
    }
    std::cout << "[RESULT] decompressed " << n_done << " frames on the PC, worst maxdiff " << worst
              << (n_bad ? "  FAIL" : "  - all bit-exact") << std::endl;
    return n_bad ? 1 : 0;
}
