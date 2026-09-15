#include "drhe_compress.h"
#include <cmath>

// Emulate two's complement int16 wraparound (matches MATLAB wrap_int16)
static inline int wrap_int16(int val) {
    return ((val + 32768) & 0xFFFF) - 32768;
}

void drhe_compress(
    hls::stream<axis_128_t>& in_stream,
    hls::stream<axis_256_t>& out_stream,
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

    // Bit Packer state registers
    ap_uint<512> bit_buffer = 0;
    int bit_count = 0;

    RAMP_LOOP: for (int r = 0; r < nRamps; r++) {
        SAMPLE_LOOP: for (int s = 0; s < nSamples; s++) {
#pragma HLS PIPELINE II=1

            axis_128_t in_pkt = in_stream.read();
            ap_uint<128> raw_in = in_pkt.data;

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

                    // Extract 32-bit complex sample for channel (16-bit Re, 16-bit Im)
                    ap_uint<32> ch_data = raw_in.range((ch + 1) * 32 - 1, ch * 32);
                    ap_int<16> re_raw = ch_data.range(15, 0);
                    ap_int<16> im_raw = ch_data.range(31, 16);
                    int re = (int)re_raw;
                    int im = (int)im_raw;

                    // 1. Model Prediction — UNIFORM formula for ALL ramps
                    float mag_pred   = ALPHA * s_mag_pred[ch][s] + (1.0f - ALPHA) * s_prev_mag[ch][s];
                    float phase_pred = BETA * s_phase_pred[ch][s] + (2.0f - BETA) * s_prev_phase[ch][s] - s_prev_prev_phase[ch][s];

                    // Phase wrap [-PI, PI]
                    if (phase_pred > (float)M_PI) {
                        phase_pred -= 2.0f * (float)M_PI;
                    } else if (phase_pred < -(float)M_PI) {
                        phase_pred += 2.0f * (float)M_PI;
                    }

                    // 2. Polar to Cartesian — with round() to match MATLAB
                    int pred_re = (int)roundf(mag_pred * hls::cos(phase_pred));
                    int pred_im = (int)roundf(mag_pred * hls::sin(phase_pred));

                    // 3. Residual with int16 wraparound (matches MATLAB wrap_int16)
                    int diff_re = wrap_int16(re - pred_re);
                    int diff_im = wrap_int16(im - pred_im);

                    // 3a. Saturate the one residual the S4/APPEND code cannot represent.
                    //     Region S4=15 spans |v| in [16384, 32767] — exactly 2^15 values, which
                    //     exactly fills the 15 APPEND bits. |v| = 32768 has no encoding, and
                    //     get_append_bits(-32768, 15) aliases onto the code for +32767. Clamping
                    //     to -32767 costs at most 1 LSB on that sample and keeps the bitstream
                    //     format unchanged. Residuals in real ColoRadar data span only about
                    //     [-514, +416], so this never fires in practice.
                    if (diff_re == -32768) diff_re = -32767;
                    if (diff_im == -32768) diff_im = -32767;

                    // 3b. Reconstruct exactly what the decompressor will produce, and drive the
                    //     prediction state from THAT rather than from the original sample.
                    //     The decompressor has no access to the original, so if the encoder
                    //     predicted from the original the two would diverge whenever 3a fires and
                    //     the IIR filters would carry that divergence forward through every
                    //     remaining ramp. Closing the loop bounds the error to the clamped sample.
                    //     When no clamping occurs, recon == original and behaviour is unchanged.
                    int recon_re = wrap_int16(diff_re + pred_re);
                    int recon_im = wrap_int16(diff_im + pred_im);

                    float re_f = (float)recon_re;
                    float im_f = (float)recon_im;
                    float curr_mag   = hls::sqrt(re_f * re_f + im_f * im_f);
                    float curr_phase = hls::atan2(im_f, re_f);

                    // 4. Update State Memory
                    s_prev_prev_phase[ch][s] = s_prev_phase[ch][s];
                    s_prev_phase[ch][s]      = curr_phase;
                    s_phase_pred[ch][s]      = phase_pred;
                    s_prev_mag[ch][s]        = curr_mag;
                    s_mag_pred[ch][s]        = mag_pred;

                    // 5. Huffman & S4 Encoding for Real and Imaginary Residuals
                    ap_uint<4> s4_re = get_s4_region(diff_re);
                    ap_uint<15> append_re = get_append_bits(diff_re, s4_re);
                    DictEntry_t huff_re = HUFFMAN_TABLE[s4_re];

                    ap_uint<4> s4_im = get_s4_region(diff_im);
                    ap_uint<15> append_im = get_append_bits(diff_im, s4_im);
                    DictEntry_t huff_im = HUFFMAN_TABLE[s4_im];

                    // Shift append bits above Huffman code (decoder reads Huffman code from LSB first)
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

            // Flush 256-bit wide output packets to AXI Stream when available
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
    }

    // Flush remaining buffer bits at end of frame
    if (bit_count > 0) {
        axis_256_t out_pkt;
        out_pkt.data = bit_buffer.range(255, 0);
        out_pkt.last = 1;
        out_pkt.keep = -1;
        out_stream.write(out_pkt);
    }
}
