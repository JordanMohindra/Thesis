#ifndef DRHE_ABL_COMMON_H
#define DRHE_ABL_COMMON_H
// ---------------------------------------------------------------------------
// Ablation harness for the DRHE compressor.
//
// One source, four independent switches, each selected at compile time with
// -D flags in the HLS config (syn.cflags / tb.cflags). With every switch at 0
// the code is, line for line, the DRHE-1 design in drhe_compress.cpp, which is
// the control: it must reproduce DRHE-1's synthesis numbers exactly.
//
//   ABL_PACK  0  original packer: eight inserts into a 512-bit buffer, each
//                shifted by a signed 32-bit int offset (drhe_compress.cpp)
//             1  same eight inserts, unsigned 10-bit offset
//             2  Kiem-style packer: real+imag of a channel packed into one
//                58-bit word, the four channel words concatenated into one
//                232-bit word, one insert into the output buffer
//             3  the most literal reading of Kiem's text: the same 58-bit
//                channel words, each inserted into the output buffer in
//                turn (four inserts), with a signed 32-bit int offset
//   ABL_RESET 0  state zeroed by a write on ramp 0 (drhe_compress.cpp)
//             1  state read as zero on ramp 0 (no extra write -> 1R+1W/array)
//   ABL_ARITH 0  single-precision float datapath (drhe_compress.cpp)
//             1  Kiem's fixed-point datapath (thesis Sec. 4.3.4): mag
//                ap_ufixed<16,16>, phase ap_fixed<16,3>, intermediates
//                ap_fixed<32,4>, hls::sqrt(ap_uint<32>), hls::atan2 on
//                ap_fixed<16,16>, hls::sin/cos on ap_fixed<16,3>
//   ABL_LOOP  0  closed loop: state driven from the reconstruction
//             1  open loop: state driven from the input sample (Kiem)
//
//   ABL_DEPTH23 (optional) force each pipelined iteration to at least 23
//                cycles, Kiem's reported latency, to measure what a deeper
//                pipeline costs in registers
//
// The bitstream format, Huffman table and S4/APPEND code are identical in all
// variants, so the same decoder reads every PACK mode; the decoder mirrors
// ABL_ARITH. Lossless in every combination (verified by the testbench).
// ---------------------------------------------------------------------------
#include "abl_variant.h"
#ifndef ABL_PACK
#define ABL_PACK 0
#endif
#ifndef ABL_RESET
#define ABL_RESET 0
#endif
#ifndef ABL_ARITH
#define ABL_ARITH 0
#endif
#ifndef ABL_LOOP
#define ABL_LOOP 0
#endif

#include "drhe_common.h"

#if ABL_ARITH == 1
typedef ap_fixed<16, 16>          k_in_t;      // integer I/Q for hls::atan2
typedef ap_fixed<16, 3>           k_phase_t;   // hls::sin/cos argument
typedef ap_ufixed<16, 16, AP_RND> k_mag_t;     // Kiem mag_data
typedef ap_fixed<16, 3, AP_RND>   k_phs_t;     // Kiem phase_data
typedef ap_fixed<32, 4, AP_RND>   k_iph_t;     // Kiem intermediate phase
typedef ap_fixed<16, 16, AP_RND>  k_fft_t;     // Kiem fft_data
const ap_ufixed<16, 0> K_ALPHA = 0.6;
const ap_ufixed<16, 0> K_1MA   = 0.4;
const ap_ufixed<16, 0> K_BETA  = 0.4;
const ap_ufixed<17, 1> K_2MB   = 1.6;
const k_iph_t K_PI   = 3.14159265358979;
const k_iph_t K_2PI  = 6.28318530717959;
typedef k_mag_t st_mag_t;
typedef k_phs_t st_phs_t;
#else
typedef float st_mag_t;
typedef float st_phs_t;
#endif

static inline int abl_wrap16(int val) { return ((val + 32768) & 0xFFFF) - 32768; }

// One DRHE model step for one channel. Shared by encoder and decoder so the two
// can never differ. Inputs are the five state words; outputs are the Cartesian
// prediction and the new magnitude/phase prediction words.
template <typename M, typename P>
static inline void abl_predict(M pmp, M pm, P ppp, P pp, P ppp2,
                               int &pred_re, int &pred_im, M &mag_pred_o, P &phase_pred_o) {
#if ABL_ARITH == 1
    k_mag_t mag_pred = K_ALPHA * pmp + K_1MA * pm;
    k_iph_t t1 = K_BETA * ppp;
    k_iph_t t2 = K_2MB * pp;
    k_iph_t tp = t1 + t2 - ppp2;
    if (tp > K_PI) tp -= K_2PI; else if (tp < -K_PI) tp += K_2PI;
    k_phs_t phase_pred = tp;
    k_phase_t ph = phase_pred;
    k_fft_t pr = mag_pred * hls::cos(ph);
    k_fft_t pi = mag_pred * hls::sin(ph);
    pred_re = pr.to_int();
    pred_im = pi.to_int();
    mag_pred_o = mag_pred; phase_pred_o = phase_pred;
#else
    float mag_pred   = ALPHA * pmp + (1.0f - ALPHA) * pm;
    float phase_pred = BETA * ppp + (2.0f - BETA) * pp - ppp2;
    if (phase_pred > (float)M_PI) phase_pred -= 2.0f * (float)M_PI;
    else if (phase_pred < -(float)M_PI) phase_pred += 2.0f * (float)M_PI;
    pred_re = (int)roundf(mag_pred * hls::cos(phase_pred));
    pred_im = (int)roundf(mag_pred * hls::sin(phase_pred));
    mag_pred_o = mag_pred; phase_pred_o = phase_pred;
#endif
}

template <typename M, typename P>
static inline void abl_polar(int re, int im, M &mag, P &phs) {
#if ABL_ARITH == 1
    ap_uint<32> sq = (ap_uint<32>)((ap_int<33>)re * re + (ap_int<33>)im * im);
    ap_uint<32> m  = hls::sqrt(sq);
    mag = (k_mag_t)m;
    phs = (k_phs_t)hls::atan2((k_in_t)im, (k_in_t)re);
#else
    float re_f = (float)re, im_f = (float)im;
    mag = hls::sqrt(re_f * re_f + im_f * im_f);
    phs = hls::atan2(im_f, re_f);
#endif
}

#endif
