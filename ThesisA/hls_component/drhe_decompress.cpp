#include "drhe_decompress.h"
#include <cmath>

// Emulate two's complement int16 wraparound (matches MATLAB wrap_int16)
static inline int wrap_int16(int val) {
    return ((val + 32768) & 0xFFFF) - 32768;
}

// Helper: Decode a single Huffman code from bit buffer
static inline bool decode_huffman_symbol(ap_uint<512>& buffer, int bit_count, ap_uint<4>& out_s4, int& out_code_len) {
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

void drhe_decompress(
    hls::stream<axis_256_t>& in_stream,
    hls::stream<axis_128_t>& out_stream,
    int nSamples,
    int nRamps,
    int nRX
) {
#pragma HLS INTERFACE axis port=in_stream
#pragma HLS INTERFACE axis port=out_stream
#pragma HLS INTERFACE s_axilite port=nSamples bundle=control
#pragma HLS INTERFACE s_axilite port=nRamps bundle=control
#pragma HLS INTERFACE s_axilite port=nRX bundle=control
#pragma HLS INTERFACE s_axilite port=return bundle=control

    // State BRAM history buffers across chirps — zero-initialized
    static float s_mag_pred[MAX_NRX][MAX_N];
    static float s_prev_mag[MAX_NRX][MAX_N];
    static float s_phase_pred[MAX_NRX][MAX_N];
    static float s_prev_phase[MAX_NRX][MAX_N];
    static float s_prev_prev_phase[MAX_NRX][MAX_N];

#pragma HLS ARRAY_PARTITION variable=s_mag_pred complete dim=1
#pragma HLS ARRAY_PARTITION variable=s_prev_mag complete dim=1
#pragma HLS ARRAY_PARTITION variable=s_phase_pred complete dim=1
#pragma HLS ARRAY_PARTITION variable=s_prev_phase complete dim=1
#pragma HLS ARRAY_PARTITION variable=s_prev_prev_phase complete dim=1

    ap_uint<512> bit_buffer = 0;
    int bit_count = 0;

    RAMP_LOOP: for (int r = 0; r < nRamps; r++) {
        SAMPLE_LOOP: for (int s = 0; s < nSamples; s++) {
#pragma HLS PIPELINE II=1

            ap_uint<128> restored_raw = 0;

            CHANNEL_LOOP: for (int ch = 0; ch < MAX_NRX; ch++) {
#pragma HLS UNROLL
                if (ch < nRX) {
                    // Reset history state at start of frame (r == 0)
                    if (r == 0) {
                        s_mag_pred[ch][s] = 0.0f;
                        s_prev_mag[ch][s] = 0.0f;
                        s_phase_pred[ch][s] = 0.0f;
                        s_prev_phase[ch][s] = 0.0f;
                        s_prev_prev_phase[ch][s] = 0.0f;
                    }

                    // Refill bit buffer if necessary
                    if (bit_count < 128 && !in_stream.empty()) {
                        axis_256_t in_pkt = in_stream.read();
                        bit_buffer |= ((ap_uint<512>)in_pkt.data << bit_count);
                        bit_count += 256;
                    }

                    // 1. Decode Real Residual
                    ap_uint<4> s4_re = 0;
                    int code_len_re = 0;
                    decode_huffman_symbol(bit_buffer, bit_count, s4_re, code_len_re);
                    bit_buffer >>= code_len_re;
                    bit_count -= code_len_re;

                    ap_uint<15> append_re = 0;
                    if (s4_re > 0) {
                        append_re = bit_buffer.range(s4_re - 1, 0);
                        bit_buffer >>= s4_re;
                        bit_count -= s4_re;
                    }
                    int diff_re = decode_append_bits(append_re, s4_re);

                    // 2. Decode Imaginary Residual
                    ap_uint<4> s4_im = 0;
                    int code_len_im = 0;
                    decode_huffman_symbol(bit_buffer, bit_count, s4_im, code_len_im);
                    bit_buffer >>= code_len_im;
                    bit_count -= code_len_im;

                    ap_uint<15> append_im = 0;
                    if (s4_im > 0) {
                        append_im = bit_buffer.range(s4_im - 1, 0);
                        bit_buffer >>= s4_im;
                        bit_count -= s4_im;
                    }
                    int diff_im = decode_append_bits(append_im, s4_im);

                    // 3. Model Prediction — UNIFORM formula for ALL ramps
                    float mag_pred   = ALPHA * s_mag_pred[ch][s] + (1.0f - ALPHA) * s_prev_mag[ch][s];
                    float phase_pred = BETA * s_phase_pred[ch][s] + (2.0f - BETA) * s_prev_phase[ch][s] - s_prev_prev_phase[ch][s];

                    // Phase wrap [-PI, PI]
                    if (phase_pred > (float)M_PI) {
                        phase_pred -= 2.0f * (float)M_PI;
                    } else if (phase_pred < -(float)M_PI) {
                        phase_pred += 2.0f * (float)M_PI;
                    }

                    // 4. Polar to Cartesian — with round() to match compressor and MATLAB
                    int pred_re = (int)roundf(mag_pred * hls::cos(phase_pred));
                    int pred_im = (int)roundf(mag_pred * hls::sin(phase_pred));

                    // 5. Reconstruct with int16 wraparound (matches MATLAB wrap_int16)
                    int re = wrap_int16(diff_re + pred_re);
                    int im = wrap_int16(diff_im + pred_im);

                    // 6. Recompute Polar for state update
                    float re_f = (float)re;
                    float im_f = (float)im;
                    float curr_mag   = hls::sqrt(re_f * re_f + im_f * im_f);
                    float curr_phase = hls::atan2(im_f, re_f);

                    // 7. Update State Memory (matches compressor exactly)
                    s_prev_prev_phase[ch][s] = s_prev_phase[ch][s];
                    s_prev_phase[ch][s]      = curr_phase;
                    s_phase_pred[ch][s]      = phase_pred;
                    s_prev_mag[ch][s]        = curr_mag;
                    s_mag_pred[ch][s]        = mag_pred;

                    // Pack into 32-bit channel output
                    ap_uint<32> ch_out;
                    ch_out.range(15, 0) = (ap_uint<16>)(ap_int<16>)re;
                    ch_out.range(31, 16) = (ap_uint<16>)(ap_int<16>)im;

                    restored_raw.range((ch + 1) * 32 - 1, ch * 32) = ch_out;
                }
            }

            // Output Restored 128-bit Sample
            axis_128_t out_pkt;
            out_pkt.data = restored_raw;
            out_pkt.last = (r == nRamps - 1 && s == nSamples - 1) ? 1 : 0;
            out_pkt.keep = -1;
            out_stream.write(out_pkt);
        }
    }
}
