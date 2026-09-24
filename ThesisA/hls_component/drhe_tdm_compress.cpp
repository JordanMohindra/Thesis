#include "drhe_tdm_compress.h"
#include <cmath>

// Emulate two's complement int16 wraparound (matches MATLAB wrap_int16)
static inline int wrap_int16(int val) {
    return ((val + 32768) & 0xFFFF) - 32768;
}

void drhe_tdm_compress(
    hls::stream<axis_128_t>& in_stream,
    hls::stream<axis_256_t>& out_stream,
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

    // One predictor history per (channel, transmitter, range bin).
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

    int tx = 0;   // transmitter index of the current ramp: r % nTx

    RAMP_LOOP: for (int r = 0; r < nRamps; r++) {
        SAMPLE_LOOP: for (int s = 0; s < nSamples; s++) {
#pragma HLS PIPELINE II=1

            // State slot for this (transmitter, range bin) pair.
            int st = tdm_state_index(tx, s);

            axis_128_t in_pkt = in_stream.read();
            ap_uint<128> raw_in = in_pkt.data;

            CHANNEL_LOOP: for (int ch = 0; ch < MAX_NRX; ch++) {
#pragma HLS UNROLL
                if (ch < nRX) {
                    // Each transmitter's history starts on its own first ramp,
                    // i.e. on ramps 0 .. nTx-1, not only on ramp 0.
                    if (r < nTx) {
                        s_mag_pred[ch][st] = 0.0f;
                        s_prev_mag[ch][st] = 0.0f;
                        s_phase_pred[ch][st] = 0.0f;
                        s_prev_phase[ch][st] = 0.0f;
                        s_prev_prev_phase[ch][st] = 0.0f;
                    }

                    ap_uint<32> ch_data = raw_in.range((ch + 1) * 32 - 1, ch * 32);
                    ap_int<16> re_raw = ch_data.range(15, 0);
                    ap_int<16> im_raw = ch_data.range(31, 16);
                    int re = (int)re_raw;
                    int im = (int)im_raw;

                    // 1. Model prediction from the SAME transmitter's previous ramp
                    float mag_pred   = ALPHA * s_mag_pred[ch][st] + (1.0f - ALPHA) * s_prev_mag[ch][st];
                    float phase_pred = BETA * s_phase_pred[ch][st] + (2.0f - BETA) * s_prev_phase[ch][st] - s_prev_prev_phase[ch][st];

                    if (phase_pred > (float)M_PI) {
                        phase_pred -= 2.0f * (float)M_PI;
                    } else if (phase_pred < -(float)M_PI) {
                        phase_pred += 2.0f * (float)M_PI;
                    }

                    int pred_re = (int)roundf(mag_pred * hls::cos(phase_pred));
                    int pred_im = (int)roundf(mag_pred * hls::sin(phase_pred));

                    int diff_re = wrap_int16(re - pred_re);
                    int diff_im = wrap_int16(im - pred_im);

                    // -32768 has no S4/APPEND encoding; clamp it (see drhe_compress.cpp)
                    if (diff_re == -32768) diff_re = -32767;
                    if (diff_im == -32768) diff_im = -32767;

                    // Closed-loop: drive the state from what the decoder will see
                    int recon_re = wrap_int16(diff_re + pred_re);
                    int recon_im = wrap_int16(diff_im + pred_im);

                    float re_f = (float)recon_re;
                    float im_f = (float)recon_im;
                    float curr_mag   = hls::sqrt(re_f * re_f + im_f * im_f);
                    float curr_phase = hls::atan2(im_f, re_f);

                    s_prev_prev_phase[ch][st] = s_prev_phase[ch][st];
                    s_prev_phase[ch][st]      = curr_phase;
                    s_phase_pred[ch][st]      = phase_pred;
                    s_prev_mag[ch][st]        = curr_mag;
                    s_mag_pred[ch][st]        = mag_pred;

                    ap_uint<4> s4_re = get_s4_region(diff_re);
                    ap_uint<15> append_re = get_append_bits(diff_re, s4_re);
                    DictEntry_t huff_re = HUFFMAN_TABLE[s4_re];

                    ap_uint<4> s4_im = get_s4_region(diff_im);
                    ap_uint<15> append_im = get_append_bits(diff_im, s4_im);
                    DictEntry_t huff_im = HUFFMAN_TABLE[s4_im];

                    ap_uint<32> code_re = ((ap_uint<32>)append_re << huff_re.len) | (ap_uint<32>)huff_re.code;
                    int len_re = huff_re.len + s4_re;

                    ap_uint<32> code_im = ((ap_uint<32>)append_im << huff_im.len) | (ap_uint<32>)huff_im.code;
                    int len_im = huff_im.len + s4_im;

                    bit_buffer |= ((ap_uint<512>)code_re << bit_count);
                    bit_count += len_re;

                    bit_buffer |= ((ap_uint<512>)code_im << bit_count);
                    bit_count += len_im;
                }
            }

            if (bit_count >= 256) {
                axis_256_t out_pkt;
                out_pkt.data = bit_buffer.range(255, 0);
                out_pkt.last = 0;
                out_pkt.keep = -1;
                out_stream.write(out_pkt);

                bit_buffer >>= 256;
                bit_count -= 256;
            }
        }

        tx++;
        if (tx == nTx) tx = 0;
    }

    if (bit_count > 0) {
        axis_256_t out_pkt;
        out_pkt.data = bit_buffer.range(255, 0);
        out_pkt.last = 1;
        out_pkt.keep = -1;
        out_stream.write(out_pkt);
    }
}
