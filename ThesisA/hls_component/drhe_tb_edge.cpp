// ============================================================================
//  drhe_tb_edge.cpp - Test 2.4, edge case verification for the DRHE codec.
//
//  Feeds synthetically generated degenerate frames through
//  drhe_compress() -> drhe_decompress() and checks that reconstruction is
//  bit-exact in every case. No input file is required; all data is generated
//  in the testbench, so this runs standalone in C-simulation and co-simulation.
//
//  The point of these cases is robustness, not compression ratio. A lossless
//  predictive coder must reproduce its input exactly whatever the input looks
//  like, including inputs that make it expand rather than compress.
// ============================================================================

#include <iostream>
#include <iomanip>
#include <vector>
#include <string>
#include <cstdint>
#include <cstdlib>
#include <cmath>

#include "drhe_compress.h"
#include "drhe_decompress.h"

// ---------------------------------------------------------------------------
// Deterministic PRNG (xorshift32). std::rand is not reproducible across
// compilers, and these results need to be identical in csim and cosim.
// ---------------------------------------------------------------------------
static uint32_t g_rng_state = 0x12345678u;
static inline void rng_seed(uint32_t s) { g_rng_state = s ? s : 1u; }
static inline uint32_t rng_next() {
    uint32_t x = g_rng_state;
    x ^= x << 13; x ^= x >> 17; x ^= x << 5;
    g_rng_state = x;
    return x;
}

enum CaseKind {
    CASE_ZEROS,        // every sample zero
    CASE_DC,           // constant non-zero everywhere
    CASE_RANDOM,       // uniform random int16 - incompressible
    CASE_SINE_MULTI,   // realistic windowed tone, full ramp count
    CASE_SINE_SINGLE,  // same tone, nRamps = 1 (no prediction history)
    CASE_MAX_CONST,    // every sample at +32767
    CASE_MAX_ALT,      // +32767 / -32768 alternating per ramp (worst-case wrap)
    CASE_INT16_MIN     // every sample at -32768 (asymmetry of two's complement)
};

struct EdgeCase {
    const char* name;
    CaseKind    kind;
    uint32_t    nSamples;
    uint32_t    nRamps;
    uint32_t    nRX;
    const char* expectation;
};

// ---------------------------------------------------------------------------
// Sample generator. Must be a pure function of (kind, r, s, ch) except for the
// random case, which is driven by the seeded PRNG in traversal order.
// ---------------------------------------------------------------------------
static void gen_sample(CaseKind kind, uint32_t r, uint32_t s, uint32_t ch,
                       int16_t& re, int16_t& im)
{
    switch (kind) {
    case CASE_ZEROS:
        re = 0; im = 0;
        break;

    case CASE_DC:
        re = (int16_t)1000; im = (int16_t)(-500);
        break;

    case CASE_RANDOM: {
        uint32_t v = rng_next();
        re = (int16_t)(v & 0xFFFF);
        im = (int16_t)((v >> 16) & 0xFFFF);
        break;
    }

    case CASE_SINE_MULTI:
    case CASE_SINE_SINGLE: {
        // A slowly rotating tone across ramps - the kind of correlated data
        // DRHE is designed for. Amplitude well inside int16.
        double ph = 0.15 * (double)s + 0.03 * (double)r + 0.5 * (double)ch;
        double a  = 8000.0;
        re = (int16_t)(a * std::cos(ph));
        im = (int16_t)(a * std::sin(ph));
        break;
    }

    case CASE_MAX_CONST:
        re = (int16_t)32767; im = (int16_t)32767;
        break;

    case CASE_MAX_ALT:
        if ((r & 1u) == 0u) { re = (int16_t)32767;  im = (int16_t)(-32768); }
        else                { re = (int16_t)(-32768); im = (int16_t)32767;  }
        break;

    case CASE_INT16_MIN:
        re = (int16_t)(-32768); im = (int16_t)(-32768);
        break;
    }
}

struct Result {
    std::string name;
    uint32_t nSamples, nRamps, nRX;
    long   inBits, outBits;
    double cr;
    int    maxDiff;
    bool   pass;
};

// ---------------------------------------------------------------------------
static Result run_case(const EdgeCase& ec)
{
    struct Sample { int re[MAX_NRX]; int im[MAX_NRX]; };
    std::vector<std::vector<Sample> > orig(ec.nRamps, std::vector<Sample>(ec.nSamples));

    hls::stream<axis_128_t> cin("cin");
    hls::stream<axis_256_t> cout_("cout");
    hls::stream<axis_128_t> dout("dout");

    rng_seed(0xC0FFEEu);   // reset per case so results are reproducible

    for (uint32_t r = 0; r < ec.nRamps; r++) {
        for (uint32_t s = 0; s < ec.nSamples; s++) {
            axis_128_t pkt;
            ap_uint<128> raw = 0;
            for (uint32_t ch = 0; ch < ec.nRX; ch++) {
                int16_t re = 0, im = 0;
                gen_sample(ec.kind, r, s, ch, re, im);
                orig[r][s].re[ch] = (int)re;
                orig[r][s].im[ch] = (int)im;

                ap_uint<32> w = 0;
                w.range(15, 0)  = (ap_uint<16>)(ap_int<16>)re;
                w.range(31, 16) = (ap_uint<16>)(ap_int<16>)im;
                raw.range((ch + 1) * 32 - 1, ch * 32) = w;
            }
            pkt.data = raw;
            pkt.last = (r == ec.nRamps - 1 && s == ec.nSamples - 1) ? 1 : 0;
            pkt.keep = -1;
            cin.write(pkt);
        }
    }

    drhe_compress(cin, cout_, ec.nSamples, ec.nRamps, ec.nRX);

    long nPkts   = (long)cout_.size();
    long inBits  = (long)ec.nRamps * ec.nSamples * ec.nRX * 32;
    long outBits = nPkts * 256;

    drhe_decompress(cout_, dout, ec.nSamples, ec.nRamps, ec.nRX);

    int maxDiff = 0;
    bool underflow = false;
    for (uint32_t r = 0; r < ec.nRamps && !underflow; r++) {
        for (uint32_t s = 0; s < ec.nSamples; s++) {
            if (dout.empty()) { underflow = true; break; }
            ap_uint<128> raw = dout.read().data;
            for (uint32_t ch = 0; ch < ec.nRX; ch++) {
                ap_uint<32> w = raw.range((ch + 1) * 32 - 1, ch * 32);
                ap_int<16> rre = w.range(15, 0);
                ap_int<16> rim = w.range(31, 16);
                int dr = std::abs((int)rre - orig[r][s].re[ch]);
                int di = std::abs((int)rim - orig[r][s].im[ch]);
                if (dr > maxDiff) maxDiff = dr;
                if (di > maxDiff) maxDiff = di;
            }
        }
    }

    Result res;
    res.name     = ec.name;
    res.nSamples = ec.nSamples;
    res.nRamps   = ec.nRamps;
    res.nRX      = ec.nRX;
    res.inBits   = inBits;
    res.outBits  = outBits;
    res.cr       = outBits ? (double)inBits / (double)outBits : 0.0;
    res.maxDiff  = maxDiff;
    res.pass     = (!underflow) && (maxDiff == 0);

    if (underflow) {
        std::cout << "  [ERROR] " << ec.name
                  << ": decompressor produced too few samples" << std::endl;
    }
    return res;
}

// ---------------------------------------------------------------------------
int main()
{
    std::cout << "==========================================================" << std::endl;
    std::cout << " DRHE Edge Case Testbench  (Test 2.4)                     " << std::endl;
    std::cout << " Synthetic degenerate inputs - no data file required      " << std::endl;
    std::cout << "==========================================================" << std::endl;

    const EdgeCase cases[] = {
        { "all-zeros",      CASE_ZEROS,       128, 192, 4, "CR very high, lossless"        },
        { "dc-constant",    CASE_DC,          128, 192, 4, "CR very high, lossless"        },
        { "random-int16",   CASE_RANDOM,      128, 192, 4, "incompressible, lossless"      },
        { "tone-192ramp",   CASE_SINE_MULTI,  128, 192, 4, "baseline for the 1-ramp case"  },
        { "tone-1ramp",     CASE_SINE_SINGLE, 128,   1, 4, "no prediction history"         },
        { "max-amplitude",  CASE_MAX_CONST,   128, 192, 4, "no overflow at +32767"         },
        { "max-alternating",CASE_MAX_ALT,     128, 192, 4, "worst-case two's-comp wrap"    },
        { "int16-min",      CASE_INT16_MIN,   128, 192, 4, "asymmetric -32768"             }
    };
    const int nCases = (int)(sizeof(cases) / sizeof(cases[0]));

    std::vector<Result> results;
    for (int i = 0; i < nCases; i++) {
        std::cout << "\n[" << (i + 1) << "/" << nCases << "] " << cases[i].name
                  << "  (" << cases[i].nRamps << " ramps x " << cases[i].nSamples
                  << " samples x " << cases[i].nRX << " RX)  - " << cases[i].expectation
                  << std::endl;
        Result r = run_case(cases[i]);
        results.push_back(r);
        std::cout << "      CR=" << std::fixed << std::setprecision(4) << r.cr
                  << "  bits " << r.inBits << " -> " << r.outBits
                  << "  MaxDiff=" << r.maxDiff
                  << (r.pass ? "  [LOSSLESS]" : "  [FAIL]") << std::endl;
    }

    std::cout << "\n==========================================================" << std::endl;
    std::cout << " EDGE CASE SUMMARY" << std::endl;
    std::cout << "==========================================================" << std::endl;
    std::cout << std::left  << std::setw(18) << "case"
              << std::right << std::setw(10) << "CR"
              << std::setw(10) << "MaxDiff"
              << std::setw(10) << "result" << std::endl;

    int nPass = 0;
    for (size_t i = 0; i < results.size(); i++) {
        const Result& r = results[i];
        if (r.pass) nPass++;
        std::cout << std::left  << std::setw(18) << r.name
                  << std::right << std::setw(10) << std::fixed << std::setprecision(4) << r.cr
                  << std::setw(10) << r.maxDiff
                  << std::setw(10) << (r.pass ? "PASS" : "FAIL") << std::endl;
    }

    std::cout << "----------------------------------------------------------" << std::endl;
    std::cout << " " << nPass << " / " << results.size()
              << " cases reconstructed bit-exactly" << std::endl;
    std::cout << "==========================================================" << std::endl;

    if (nPass != (int)results.size()) {
        std::cout << "[FAILURE] At least one edge case was not lossless." << std::endl;
        return 1;
    }
    std::cout << "[SUCCESS] All edge cases lossless." << std::endl;
    return 0;
}
