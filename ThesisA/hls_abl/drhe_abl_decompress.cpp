// Reference decoder for the ablation harness (testbench only, not synthesised).
// Mirrors ABL_ARITH; the bitstream is the same for every ABL_PACK mode.
#include "drhe_abl_compress.h"
#include <cmath>

static inline bool abl_decode_huff(ap_uint<512>& buffer, int bit_count, ap_uint<4>& out_s4, int& out_len) {
    for (int i = 0; i < 16; i++) {
        int len = HUFFMAN_TABLE[i].len;
        if (bit_count >= len) {
            ap_uint<14> cand = buffer.range(len - 1, 0);
            if (cand == HUFFMAN_TABLE[i].code) { out_s4 = i; out_len = len; return true; }
        }
    }
    return false;
}

void drhe_abl_decompress(hls::stream<axis_256_t>& in_stream, hls::stream<axis_128_t>& out_stream,
                         int nSamples, int nRamps, int nRX) {
    static st_mag_t s_mag_pred[MAX_NRX][MAX_N];
    static st_mag_t s_prev_mag[MAX_NRX][MAX_N];
    static st_phs_t s_phase_pred[MAX_NRX][MAX_N];
    static st_phs_t s_prev_phase[MAX_NRX][MAX_N];
    static st_phs_t s_prev_prev_phase[MAX_NRX][MAX_N];
    ap_uint<512> bit_buffer = 0;
    int bit_count = 0;
    for (int r = 0; r < nRamps; r++) {
        for (int s = 0; s < nSamples; s++) {
            ap_uint<128> restored = 0;
            for (int ch = 0; ch < MAX_NRX; ch++) {
                if (ch >= nRX) continue;
                if (r == 0) {
                    s_mag_pred[ch][s] = 0; s_prev_mag[ch][s] = 0;
                    s_phase_pred[ch][s] = 0; s_prev_phase[ch][s] = 0; s_prev_prev_phase[ch][s] = 0;
                }
                if (bit_count < 128 && !in_stream.empty()) {
                    axis_256_t p = in_stream.read();
                    bit_buffer |= ((ap_uint<512>)p.data << bit_count);
                    bit_count += 256;
                }
                int d[2];
                for (int part = 0; part < 2; part++) {
                    ap_uint<4> s4 = 0; int cl = 0;
                    abl_decode_huff(bit_buffer, bit_count, s4, cl);
                    bit_buffer >>= cl; bit_count -= cl;
                    ap_uint<15> app = 0;
                    if (s4 > 0) { app = bit_buffer.range(s4 - 1, 0); bit_buffer >>= s4; bit_count -= s4; }
                    d[part] = decode_append_bits(app, s4);
                }
                int pred_re, pred_im; st_mag_t mag_pred; st_phs_t phase_pred;
                abl_predict(s_mag_pred[ch][s], s_prev_mag[ch][s], s_phase_pred[ch][s],
                            s_prev_phase[ch][s], s_prev_prev_phase[ch][s],
                            pred_re, pred_im, mag_pred, phase_pred);
                int re = abl_wrap16(d[0] + pred_re);
                int im = abl_wrap16(d[1] + pred_im);
                st_mag_t cm; st_phs_t cp;
                abl_polar(re, im, cm, cp);
                s_prev_prev_phase[ch][s] = s_prev_phase[ch][s];
                s_prev_phase[ch][s] = cp;
                s_phase_pred[ch][s] = phase_pred;
                s_prev_mag[ch][s] = cm;
                s_mag_pred[ch][s] = mag_pred;
                ap_uint<32> w;
                w.range(15, 0)  = (ap_uint<16>)(ap_int<16>)re;
                w.range(31, 16) = (ap_uint<16>)(ap_int<16>)im;
                restored.range((ch + 1) * 32 - 1, ch * 32) = w;
            }
            axis_128_t o; o.data = restored; o.keep = -1;
            o.last = (r == nRamps - 1 && s == nSamples - 1);
            out_stream.write(o);
        }
    }
}
