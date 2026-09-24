#include "drhe_tdm_decompress.h"
#include <cmath>

static inline int wrap_int16(int val) {
    return ((val + 32768) & 0xFFFF) - 32768;
}

static inline bool tdm_decode_huffman_symbol(ap_uint<512>& buffer, int bit_count, ap_uint<4>& out_s4, int& out_code_len) {
    for (int i = 0; i < 16; i++) {
        int len = HUFFMAN_TABLE[i].len;
        if (bit_count >= len) {
            ap_uint<14> candidate = buffer.range(len - 1, 0);
            if (candidate == HUFFMAN_TABLE[i].code) {
                out_s4 = i;
                out_code_len = len;
                return true;
            }
        }
    }
    return false;
}

void drhe_tdm_decompress(
    hls::stream<axis_256_t>& in_stream,
    hls::stream<axis_128_t>& out_stream,
    int nSamples,
    int nRamps,
    int nRX,
    int nTx
) {
#pragma HLS INTERFACE axis port=in_stream
#pragma HLS INTERFACE axis port=out_stream
#pragma HLS INTERFACE s_axilite port=nSamples bundle=control
#pragma HLS INTERFACE s_axilite port=nRamps bundle=control
#pragma HLS INTERFACE s_axilite port=nRX bundle=control
#pragma HLS INTERFACE s_axilite port=nTx bundle=control
#pragma HLS INTERFACE s_axilite port=return bundle=control

    static float s_mag_pred[MAX_NRX][TDM_STATE_SIZE];
    static float s_prev_mag[MAX_NRX][TDM_STATE_SIZE];
    static float s_phase_pred[MAX_NRX][TDM_STATE_SIZE];
    static float s_prev_phase[MAX_NRX][TDM_STATE_SIZE];
    static float s_prev_prev_phase[MAX_NRX][TDM_STATE_SIZE];

#pragma HLS ARRAY_PARTITION variable=s_mag_pred complete dim=1
#pragma HLS ARRAY_PARTITION variable=s_prev_mag complete dim=1
#pragma HLS ARRAY_PARTITION variable=s_phase_pred complete dim=1
#pragma HLS ARRAY_PARTITION variable=s_prev_phase complete dim=1
#pragma HLS ARRAY_PARTITION variable=s_prev_prev_phase complete dim=1

    ap_uint<512> bit_buffer = 0;
    int bit_count = 0;

    int tx = 0;

    RAMP_LOOP: for (int r = 0; r < nRamps; r++) {
        SAMPLE_LOOP: for (int s = 0; s < nSamples; s++) {
#pragma HLS PIPELINE II=1

            int st = tdm_state_index(tx, s);
            ap_uint<128> restored_raw = 0;

            CHANNEL_LOOP: for (int ch = 0; ch < MAX_NRX; ch++) {
#pragma HLS UNROLL
                if (ch < nRX) {
                    if (r < nTx) {
                        s_mag_pred[ch][st] = 0.0f;
                        s_prev_mag[ch][st] = 0.0f;
                        s_phase_pred[ch][st] = 0.0f;
                        s_prev_phase[ch][st] = 0.0f;
                        s_prev_prev_phase[ch][st] = 0.0f;
                    }

                    if (bit_count < 128 && !in_stream.empty()) {
                        axis_256_t in_pkt = in_stream.read();
                        bit_buffer |= ((ap_uint<512>)in_pkt.data << bit_count);
                        bit_count += 256;
                    }

                    ap_uint<4> s4_re = 0;
                    int code_len_re = 0;
                    tdm_decode_huffman_symbol(bit_buffer, bit_count, s4_re, code_len_re);
                    bit_buffer >>= code_len_re;
                    bit_count -= code_len_re;

                    ap_uint<15> append_re = 0;
                    if (s4_re > 0) {
                        append_re = bit_buffer.range(s4_re - 1, 0);
                        bit_buffer >>= s4_re;
                        bit_count -= s4_re;
                    }
                    int diff_re = decode_append_bits(append_re, s4_re);

                    ap_uint<4> s4_im = 0;
                    int code_len_im = 0;
                    tdm_decode_huffman_symbol(bit_buffer, bit_count, s4_im, code_len_im);
                    bit_buffer >>= code_len_im;
                    bit_count -= code_len_im;

                    ap_uint<15> append_im = 0;
                    if (s4_im > 0) {
                        append_im = bit_buffer.range(s4_im - 1, 0);
                        bit_buffer >>= s4_im;
                        bit_count -= s4_im;
                    }
                    int diff_im = decode_append_bits(append_im, s4_im);

                    float mag_pred   = ALPHA * s_mag_pred[ch][st] + (1.0f - ALPHA) * s_prev_mag[ch][st];
                    float phase_pred = BETA * s_phase_pred[ch][st] + (2.0f - BETA) * s_prev_phase[ch][st] - s_prev_prev_phase[ch][st];

                    if (phase_pred > (float)M_PI) {
                        phase_pred -= 2.0f * (float)M_PI;
                    } else if (phase_pred < -(float)M_PI) {
                        phase_pred += 2.0f * (float)M_PI;
                    }

                    int pred_re = (int)roundf(mag_pred * hls::cos(phase_pred));
                    int pred_im = (int)roundf(mag_pred * hls::sin(phase_pred));

                    int re = wrap_int16(diff_re + pred_re);
                    int im = wrap_int16(diff_im + pred_im);

                    float re_f = (float)re;
                    float im_f = (float)im;
                    float curr_mag   = hls::sqrt(re_f * re_f + im_f * im_f);
                    float curr_phase = hls::atan2(im_f, re_f);

                    s_prev_prev_phase[ch][st] = s_prev_phase[ch][st];
                    s_prev_phase[ch][st]      = curr_phase;
                    s_phase_pred[ch][st]      = phase_pred;
                    s_prev_mag[ch][st]        = curr_mag;
                    s_mag_pred[ch][st]        = mag_pred;

                    ap_uint<32> ch_out;
                    ch_out.range(15, 0) = (ap_uint<16>)(ap_int<16>)re;
                    ch_out.range(31, 16) = (ap_uint<16>)(ap_int<16>)im;

                    restored_raw.range((ch + 1) * 32 - 1, ch * 32) = ch_out;
                }
            }

            axis_128_t out_pkt;
            out_pkt.data = restored_raw;
            out_pkt.last = (r == nRamps - 1 && s == nSamples - 1) ? 1 : 0;
            out_pkt.keep = -1;
            out_stream.write(out_pkt);
        }

        tx++;
        if (tx == nTx) tx = 0;
    }
}
