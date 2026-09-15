#ifndef LPC_COMMON_H
#define LPC_COMMON_H

// ===========================================================================
//  LPC + Huffman compression - shared types and helpers.
//
//  The residual entropy coder (S4 region + APPEND bits + static Huffman) is
//  identical to DRHE's, so drhe_common.h is reused for it. Everything below is
//  specific to the linear-predictive front end.
//
//  How this differs structurally from DRHE, which drives the whole design:
//
//    DRHE  predicts ramp m from an IIR filter over ramps m-1, m-2. It is
//          causal, so it streams: one pass, no frame storage.
//
//    LPC   fits a 2nd-order Yule-Walker predictor per (range bin, RX channel,
//          I/Q part) using autocorrelations R0, R1, R2 taken over ALL ramps.
//          The coefficients therefore depend on samples that have not arrived
//          yet, so the compressor cannot be single-pass: it must buffer a whole
//          frame, solve, then go back over the frame to form residuals.
//
//  That buffer is the dominant cost of LPC in hardware and is the reason the
//  frame dimensions below are compile-time bounds rather than runtime values.
// ===========================================================================

#include "drhe_common.h"

// --- Frame bounds (compile-time: they size the frame buffer) ---------------
const int LPC_MAX_N     = 128;   // range bins per chirp (positive half of FFT)
const int LPC_MAX_RAMPS = 192;   // ramps (chirps) per frame
const int LPC_MAX_NRX   = 4;     // RX channels

// --- Coefficient formats ---------------------------------------------------
//  Yule-Walker stability requires |a2| < 1 and |a1| < 1 - a2 <= 2, so a1 needs
//  two integer bits and a2 needs one. Both are 16 bits wide, which is exactly
//  the per-coefficient budget the MATLAB overhead model charges
//  (nRangeBins * nRx * 4 coefficients * 16 bits).
//
//  Measured on ColoRadar: a1 in [-0.774, 0.875], a2 in [-0.732, 0.479], and
//  quantising to these formats costs 0.0001% of compression ratio.
typedef ap_fixed<16, 2> lpc_a1_t;    // step 2^-14
typedef ap_fixed<16, 1> lpc_a2_t;    // step 2^-15

//  Prediction accumulator. a1*prev can reach 2*32768 = 65536, so 22 integer
//  bits leaves generous headroom; 18 fractional bits preserves both
//  coefficient formats exactly.
typedef ap_fixed<40, 22> lpc_pred_t;

// --- Coefficient bit packing (for the compressed stream) -------------------
inline ap_uint<16> lpc_pack_a1(lpc_a1_t v) { ap_uint<16> b; b = v.range(15, 0); return b; }
inline ap_uint<16> lpc_pack_a2(lpc_a2_t v) { ap_uint<16> b; b = v.range(15, 0); return b; }

inline lpc_a1_t lpc_unpack_a1(ap_uint<16> b) { lpc_a1_t v; v.range(15, 0) = b; return v; }
inline lpc_a2_t lpc_unpack_a2(ap_uint<16> b) { lpc_a2_t v; v.range(15, 0) = b; return v; }

// --- Rounding --------------------------------------------------------------
//  MATLAB's round() is half-away-from-zero. Casting ap_fixed to int truncates
//  toward zero, so adding/subtracting a half before the cast reproduces it.
inline int lpc_round(lpc_pred_t v) {
    if (v >= (lpc_pred_t)0) return (int)(v + (lpc_pred_t)0.5);
    else                    return (int)(v - (lpc_pred_t)0.5);
}

// --- Two's complement int16 wraparound (matches MATLAB wrap_int16) ---------
inline int lpc_wrap_int16(int val) {
    return ((val + 32768) & 0xFFFF) - 32768;
}

// ---------------------------------------------------------------------------
//  Solve the 2nd-order Yule-Walker system for one sequence.
//
//      a1 = R1*(R0 - R2) / (R0^2 - R1^2)
//      a2 = (R0*R2 - R1^2) / (R0^2 - R1^2)
//
//  R0, R1, R2 arrive as exact 64-bit integer sums. Their products reach
//  192 * 32768^2 squared = 4.3e22, which needs 75 bits, so the numerators and
//  the determinant are formed in 128-bit integers and stay exact. Only the
//  final ratio is taken in floating point.
//
//  Forming them exactly before dividing matters: for strongly correlated data
//  R1 approaches R0, so evaluating R0^2 - R1^2 in floating point would lose
//  most of its significant digits to cancellation - precisely in the regime
//  the predictor is designed for.
// ---------------------------------------------------------------------------
//  Magnitude of a 128-bit signed value.
inline ap_uint<128> lpc_abs128(ap_int<128> v) {
    return (v < 0) ? (ap_uint<128>)(-v) : (ap_uint<128>)v;
}

//  Index of the most significant set bit, by binary search (7 steps rather
//  than a 128-iteration scan, which matters because this runs once per
//  coefficient solve).
inline int lpc_msb_index(ap_uint<128> m) {
    int n = 0;
    if (m >> 64) { n += 64; m >>= 64; }
    if (m >> 32) { n += 32; m >>= 32; }
    if (m >> 16) { n += 16; m >>= 16; }
    if (m >> 8)  { n += 8;  m >>= 8;  }
    if (m >> 4)  { n += 4;  m >>= 4;  }
    if (m >> 2)  { n += 2;  m >>= 2;  }
    if (m >> 1)  { n += 1; }
    return n;
}

inline void lpc_solve_order2(ap_int<64> R0, ap_int<64> R1, ap_int<64> R2,
                             lpc_a1_t& a1_out, lpc_a2_t& a2_out)
{
    ap_int<128> R0w = (ap_int<128>)R0;
    ap_int<128> R1w = (ap_int<128>)R1;
    ap_int<128> R2w = (ap_int<128>)R2;

    ap_int<128> det = R0w * R0w - R1w * R1w;
    ap_int<128> n1  = R1w * (R0w - R2w);
    ap_int<128> n2  = R0w * R2w - R1w * R1w;

    float a1f = 0.0f, a2f = 0.0f;
    if (det != 0) {
        //  Vitis HLS cannot convert an ap_int<128> to float above about 64
        //  significant bits - (float)(1<<70) evaluates to 0 - so the three
        //  128-bit quantities are first normalised by a common arithmetic
        //  right shift until the largest fits in 62 bits. Shifting all three
        //  by the same amount leaves both ratios unchanged, and the discarded
        //  bits are ~2^-61 relative, far below the 2^-14 coefficient
        //  quantisation step.
        int k = lpc_msb_index(lpc_abs128(det));
        int k1 = lpc_msb_index(lpc_abs128(n1));
        int k2 = lpc_msb_index(lpc_abs128(n2));
        if (k1 > k) k = k1;
        if (k2 > k) k = k2;
        k -= 61;
        if (k < 0) k = 0;

        ap_int<64> det_s = (ap_int<64>)(det >> k);
        ap_int<64> n1_s  = (ap_int<64>)(n1  >> k);
        ap_int<64> n2_s  = (ap_int<64>)(n2  >> k);

        if (det_s == 0) {
            a1_out = (lpc_a1_t)0;
            a2_out = (lpc_a2_t)0;
            return;
        }

        float fdet = (float)det_s;
        a1f = (float)n1_s / fdet;
        a2f = (float)n2_s / fdet;

        // Stability constraint, as in compute_lpc_order2 in the MATLAB.
        float abs_a1 = (a1f < 0.0f) ? -a1f : a1f;
        float abs_a2 = (a2f < 0.0f) ? -a2f : a2f;
        if (abs_a2 >= 1.0f || abs_a1 >= (1.0f - a2f)) {
            a1f = 0.0f;
            a2f = 0.0f;
        }
    }

    // Clamp into the representable range before quantising, so a coefficient
    // can never wrap around to the opposite sign.
    const float A1_MAX =  1.99993896484375f;   // 2 - 2^-14
    const float A1_MIN = -2.0f;
    const float A2_MAX =  0.999969482421875f;  // 1 - 2^-15
    const float A2_MIN = -1.0f;
    if (a1f > A1_MAX) a1f = A1_MAX;
    if (a1f < A1_MIN) a1f = A1_MIN;
    if (a2f > A2_MAX) a2f = A2_MAX;
    if (a2f < A2_MIN) a2f = A2_MIN;

    a1_out = (lpc_a1_t)a1f;
    a2_out = (lpc_a2_t)a2f;
}

#endif // LPC_COMMON_H
