#include "lpc_decompress.h"

// Decode one Huffman code from the LSB end of the buffer. The reversed code
// set is suffix-free, so at most one table entry can match. Identical to the
// helper in drhe_decompress.cpp.
static inline bool lpc_decode_huffman_symbol(ap_uint<512>& buffer, int bit_count,
                                             ap_uint<4>& out_s4, int& out_code_len) {
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

// ===========================================================================
//  LPC + Huffman decompressor.
//
//  Note the asymmetry with the compressor: because the compressor emits
//  residuals in the original raster order, this side needs no frame buffer at
//  all. It keeps only the coefficient table and two previous reconstructed
//  samples per (channel, range bin) - the same shape of state DRHE uses - and
//  writes each output sample as soon as its residual arrives.
// ===========================================================================

void lpc_decompress(
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

    static lpc_a1_t a1_re[LPC_MAX_NRX][LPC_MAX_N];
    static lpc_a2_t a2_re[LPC_MAX_NRX][LPC_MAX_N];
    static lpc_a1_t a1_im[LPC_MAX_NRX][LPC_MAX_N];
    static lpc_a2_t a2_im[LPC_MAX_NRX][LPC_MAX_N];
#pragma HLS ARRAY_PARTITION variable=a1_re complete dim=1
#pragma HLS ARRAY_PARTITION variable=a2_re complete dim=1
#pragma HLS ARRAY_PARTITION variable=a1_im complete dim=1
#pragma HLS ARRAY_PARTITION variable=a2_im complete dim=1

    static short v1_re[LPC_MAX_NRX][LPC_MAX_N];
    static short v2_re[LPC_MAX_NRX][LPC_MAX_N];
    static short v1_im[LPC_MAX_NRX][LPC_MAX_N];
    static short v2_im[LPC_MAX_NRX][LPC_MAX_N];
#pragma HLS ARRAY_PARTITION variable=v1_re complete dim=1
#pragma HLS ARRAY_PARTITION variable=v2_re complete dim=1
#pragma HLS ARRAY_PARTITION variable=v1_im complete dim=1
#pragma HLS ARRAY_PARTITION variable=v2_im complete dim=1

    ap_uint<512> bit_buffer = 0;
    int bit_count = 0;

    // ---- Coefficient table: 64 bits per (channel, range bin) --------------
    COEF_CH: for (int ch = 0; ch < LPC_MAX_NRX; ch++) {
        if (ch >= nRX) continue;
        COEF_BIN: for (int n = 0; n < nSamples; n++) {
            if (bit_count < 64) {
                axis_256_t in_pkt = in_stream.read();
                bit_buffer |= ((ap_uint<512>)in_pkt.data << bit_count);
                bit_count += 256;
            }
            ap_uint<64> word = bit_buffer.range(63, 0);
            bit_buffer >>= 64;
            bit_count -= 64;

            a1_re[ch][n] = lpc_unpack_a1((ap_uint<16>)(word.range(15, 0)));
            a2_re[ch][n] = lpc_unpack_a2((ap_uint<16>)(word.range(31, 16)));
            a1_im[ch][n] = lpc_unpack_a1((ap_uint<16>)(word.range(47, 32)));
            a2_im[ch][n] = lpc_unpack_a2((ap_uint<16>)(word.range(63, 48)));

            v1_re[ch][n] = 0; v2_re[ch][n] = 0;
            v1_im[ch][n] = 0; v2_im[ch][n] = 0;
        }
    }

    // ---- Residuals, in the same raster order the samples had --------------
    DEC_RAMP: for (int r = 0; r < nRamps; r++) {
        DEC_SAMPLE: for (int s = 0; s < nSamples; s++) {
            ap_uint<128> raw_out = 0;

            DEC_CH: for (int ch = 0; ch < LPC_MAX_NRX; ch++) {
                if (ch < nRX) {
                    // Worst case for one channel is two symbols of 14-bit
                    // code + 15 APPEND bits = 58 bits; refill well clear of it.
                    if (bit_count < 128 && !in_stream.empty()) {
                        axis_256_t in_pkt = in_stream.read();
                        bit_buffer |= ((ap_uint<512>)in_pkt.data << bit_count);
                        bit_count += 256;
                    }

                    int dval[2];
                    DEC_PART: for (int part = 0; part < 2; part++) {
                        ap_uint<4> s4 = 0;
                        int clen = 0;
                        lpc_decode_huffman_symbol(bit_buffer, bit_count, s4, clen);
                        bit_buffer >>= clen;
                        bit_count -= clen;

                        ap_uint<15> append = 0;
                        if (s4 > 0) {
                            append = bit_buffer.range(s4 - 1, 0);
                            bit_buffer >>= s4;
                            bit_count -= s4;
                        }
                        dval[part] = decode_append_bits(append, s4);
                    }

                    lpc_a1_t A1r = a1_re[ch][s], A1i = a1_im[ch][s];
                    lpc_a2_t A2r = a2_re[ch][s], A2i = a2_im[ch][s];
                    int q1r = (int)v1_re[ch][s], q2r = (int)v2_re[ch][s];
                    int q1i = (int)v1_im[ch][s], q2i = (int)v2_im[ch][s];

                    lpc_pred_t pr = (lpc_pred_t)A1r * (lpc_pred_t)q1r + (lpc_pred_t)A2r * (lpc_pred_t)q2r;
                    lpc_pred_t pi = (lpc_pred_t)A1i * (lpc_pred_t)q1i + (lpc_pred_t)A2i * (lpc_pred_t)q2i;

                    int rec_re = lpc_wrap_int16(dval[0] + lpc_round(pr));
                    int rec_im = lpc_wrap_int16(dval[1] + lpc_round(pi));

                    v2_re[ch][s] = (short)q1r; v1_re[ch][s] = (short)rec_re;
                    v2_im[ch][s] = (short)q1i; v1_im[ch][s] = (short)rec_im;

                    ap_uint<32> w = 0;
                    w.range(15, 0)  = (ap_uint<16>)(ap_int<16>)rec_re;
                    w.range(31, 16) = (ap_uint<16>)(ap_int<16>)rec_im;
                    raw_out.range((ch + 1) * 32 - 1, ch * 32) = w;
                }
            }

            axis_128_t out_pkt;
            out_pkt.data = raw_out;
            out_pkt.last = (r == nRamps - 1 && s == nSamples - 1) ? 1 : 0;
            out_pkt.keep = -1;
            out_stream.write(out_pkt);
        }
    }
}
