// radar_fe_tb.cpp - C simulation of the range-FFT front end.
//  Feeds raw_adc_multiframe.bin (raw ColoRadar ADC, 4 RX) through radar_fe and
//  compares every output code with the MATLAB chain's FX16 codes
//  (coloradar_multiframe_matlab.bin). Writes the front end's output as
//  coloradar_multiframe_fe.bin, in the same layout, for the compressor
//  testbenches and as the golden reference for the board.
//  FE_FRAMES (compile flag) limits the number of frames, e.g. for co-simulation.
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <vector>
#include "radar_fe.h"

#ifndef FE_FRAMES
#define FE_FRAMES 50
#endif

int main() {
    FILE* fr = fopen("raw_adc_multiframe.bin", "rb");
    FILE* fm = fopen("coloradar_multiframe_matlab.bin", "rb");
    if (!fr || !fm) { printf("ERROR: input files missing\n"); return 1; }
    uint32_t hr[4], hm[4];
    if (fread(hr, 4, 4, fr) != 4 || fread(hm, 4, 4, fm) != 4) { printf("ERROR: headers\n"); return 1; }
    printf("raw: %u frames x %u samples x %u ramps x %u RX\n", hr[0], hr[1], hr[2], hr[3]);
    printf("ref: %u frames x %u bins x %u ramps x %u RX\n", hm[0], hm[1], hm[2], hm[3]);
    if (hr[1] != FE_N || hr[3] != FE_NRX || hm[1] != FE_NB || hm[2] != hr[2]) { printf("ERROR: geometry\n"); return 1; }
    const int nR = hr[2];
    int nF = (int)hr[0] < FE_FRAMES ? (int)hr[0] : FE_FRAMES;

    FILE* fo = fopen("coloradar_multiframe_fe.bin", "wb");
    uint32_t ho[4] = {(uint32_t)nF, FE_NB, (uint32_t)nR, FE_NRX};
    fwrite(ho, 4, 4, fo);

    const size_t rawWords = (size_t)FE_N * nR * FE_NRX * 2, outWords = (size_t)FE_NB * nR * FE_NRX * 2;
    std::vector<int16_t> raw(rawWords), ref(outWords), got(outWords);
    long long nvals = 0, nmis = 0, hist[5] = {0, 0, 0, 0, 0};   // diff -2..+2 (clamped)
    int maxdiff = 0, errors = 0;

    for (int f = 0; f < nF; f++) {
        if (fread(raw.data(), 2, rawWords, fr) != rawWords || fread(ref.data(), 2, outWords, fm) != outWords) {
            printf("ERROR: short read, frame %d\n", f); return 1;
        }
        hls::stream<fe_axis_t> in("in"), out("out");
        size_t i = 0;
        for (int r = 0; r < nR; r++)
            for (int s = 0; s < FE_N; s++) {
                fe_axis_t b;
                ap_uint<128> d = 0;
                for (int c = 0; c < FE_NRX; c++) {
                    d.range(32 * c + 15, 32 * c)      = (ap_uint<16>)(uint16_t)raw[i++];
                    d.range(32 * c + 31, 32 * c + 16) = (ap_uint<16>)(uint16_t)raw[i++];
                }
                b.data = d; b.keep = -1; b.strb = -1;
                b.last = (r == nR - 1) && (s == FE_N - 1);
                in.write(b);
            }
        radar_fe(in, out, nR);
        if (!in.empty()) { printf("ERROR frame %d: input not fully consumed\n", f); errors++; }
        size_t o = 0;
        int fmis = 0, fmax = 0, nlast = 0;
        for (int r = 0; r < nR; r++)
            for (int k = 0; k < FE_NB; k++) {
                if (out.empty()) { printf("ERROR frame %d: output short\n", f); return 1; }
                fe_axis_t b = out.read();
                bool want_last = (r == nR - 1) && (k == FE_NB - 1);
                if ((bool)b.last != want_last) nlast++;
                for (int c = 0; c < FE_NRX; c++)
                    for (int h = 0; h < 2; h++) {
                        int16_t v = (int16_t)(uint16_t)b.data.range(32 * c + 16 * h + 15, 32 * c + 16 * h);
                        got[o] = v;
                        int d = (int)v - (int)ref[o];
                        o++;
                        if (d) { fmis++; if (abs(d) > fmax) fmax = abs(d); }
                        hist[(d < -2 ? -2 : d > 2 ? 2 : d) + 2]++;
                    }
            }
        if (!out.empty()) { printf("ERROR frame %d: extra output\n", f); errors++; }
        if (nlast) { printf("ERROR frame %d: %d TLAST errors\n", f, nlast); errors++; }
        fwrite(got.data(), 2, outWords, fo);
        nvals += outWords; nmis += fmis; if (fmax > maxdiff) maxdiff = fmax;
        printf("frame %2d: %6d of %zu codes differ from MATLAB, max |diff| %d\n", f, fmis, outWords, fmax);
    }
    fclose(fr); fclose(fm); fclose(fo);
    printf("\nTOTAL: %lld of %lld codes differ from MATLAB (%.4f %%), max |diff| %d\n",
           nmis, nvals, 100.0 * nmis / nvals, maxdiff);
    printf("diff histogram  <=-2: %lld  -1: %lld  0: %lld  +1: %lld  >=+2: %lld\n",
           hist[0], hist[1], hist[2], hist[3], hist[4]);
    printf("wrote coloradar_multiframe_fe.bin (%d frames)\n", nF);
    if (errors || maxdiff > 1) { printf("[RESULT] FAIL\n"); return 1; }
    printf("[RESULT] PASS - front end matches MATLAB to within 1 LSB\n");
    return 0;
}
