#include "lpc_tdm_decompress.h"

static inline bool lpc_tdm_decode_huffman_symbol(ap_uint<512>& buffer, int bit_count,
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
//  TDM-MIMO aware LPC + Huffman decompressor.
//
//  Still needs no frame buffer: the compressor emits residuals in raster order,
//  so this side reconstructs each sample as its residual arrives. The only
//  change from the baseline is the depth of the reconstruction history, which
//  goes from two samples per (channel, range bin) to 2*nTx, held as a ring so
//  that nothing has to be shifted.
// ===========================================================================

void lpc_tdm_decompress(
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

    static lpc_a1_t a1_re[LPC_MAX_NRX][LPC_MAX_N];
    static lpc_a2_t a2_re[LPC_MAX_NRX][LPC_MAX_N];
    static lpc_a1_t a1_im[LPC_MAX_NRX][LPC_MAX_N];
    static lpc_a2_t a2_im[LPC_MAX_NRX][LPC_MAX_N];
#pragma HLS ARRAY_PARTITION variable=a1_re complete dim=1
#pragma HLS ARRAY_PARTITION variable=a2_re complete dim=1
#pragma HLS ARRAY_PARTITION variable=a1_im complete dim=1
#pragma HLS ARRAY_PARTITION variable=a2_im complete dim=1

    // Reconstruction ring: [channel][range bin][ramp mod 2*nTx]
    static short v_re[LPC_MAX_NRX][LPC_MAX_N][LPC_TDM_HIST];
    static short v_im[LPC_MAX_NRX][LPC_MAX_N][LPC_TDM_HIST];
#pragma HLS ARRAY_PARTITION variable=v_re complete dim=1
#pragma HLS ARRAY_PARTITION variable=v_im complete dim=1
#pragma HLS ARRAY_PARTITION variable=v_re complete dim=3
#pragma HLS ARRAY_PARTITION variable=v_im complete dim=3

    ap_uint<512> bit_buffer = 0;
    int bit_count = 0;
    bool seen_last = false;   // set once the TLAST word has been read

    const int HIST = 2 * nTx;

    // ---- Coefficient table: 64 bits per (channel, range bin) --------------
    COEF_CH: for (int ch = 0; ch < LPC_MAX_NRX; ch++) {
        if (ch >= nRX) continue;
        COEF_BIN: for (int n = 0; n < nSamples; n++) {
            if (bit_count < 64 && !seen_last) {
                axis_256_t in_pkt = in_stream.read();
                bit_buffer |= ((ap_uint<512>)in_pkt.data << bit_count);
                bit_count += 256;
                seen_last = (in_pkt.last == 1);
            }
            ap_uint<64> word = bit_buffer.range(63, 0);
            bit_buffer >>= 64;
            bit_count -= 64;

            a1_re[ch][n] = lpc_unpack_a1((ap_uint<16>)(word.range(15, 0)));
            a2_re[ch][n] = lpc_unpack_a2((ap_uint<16>)(word.range(31, 16)));
            a1_im[ch][n] = lpc_unpack_a1((ap_uint<16>)(word.range(47, 32)));
            a2_im[ch][n] = lpc_unpack_a2((ap_uint<16>)(word.range(63, 48)));

            CLR_HIST: for (int k = 0; k < LPC_TDM_HIST; k++) {
#pragma HLS UNROLL
                v_re[ch][n][k] = 0;
                v_im[ch][n][k] = 0;
            }
        }
    }

    // ---- Residuals, in the same raster order the samples had --------------
    DEC_RAMP: for (int r = 0; r < nRamps; r++) {
        int k  = r % HIST;
        int k1 = (k + nTx) % HIST;

        DEC_SAMPLE: for (int s = 0; s < nSamples; s++) {
            ap_uint<128> raw_out = 0;

            DEC_CH: for (int ch = 0; ch < LPC_MAX_NRX; ch++) {
                if (ch < nRX) {
                    // Blocking read, stopped by TLAST rather than by empty().
                    // empty() is only a safe end-of-data test in C simulation, where
                    // the whole compressed frame is already in the stream. On the
                    // board the words arrive from a DMA with variable latency, and a
                    // momentarily empty FIFO would be mistaken for the end of the
                    // data and decode garbage. The compressor marks its final word
                    // with TLAST, so stopping on it is exact in every environment.
                    if (bit_count < 128 && !seen_last) {
                        axis_256_t in_pkt = in_stream.read();
                        bit_buffer |= ((ap_uint<512>)in_pkt.data << bit_count);
                        bit_count += 256;
                        seen_last = (in_pkt.last == 1);
                    }

                    int dval[2];
                    DEC_PART: for (int part = 0; part < 2; part++) {
                        ap_uint<4> s4 = 0;
                        int clen = 0;
                        lpc_tdm_decode_huffman_symbol(bit_buffer, bit_count, s4, clen);
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

                    int q1r = (int)v_re[ch][s][k1], q2r = (int)v_re[ch][s][k];
                    int q1i = (int)v_im[ch][s][k1], q2i = (int)v_im[ch][s][k];

                    lpc_pred_t pr = (lpc_pred_t)A1r * (lpc_pred_t)q1r + (lpc_pred_t)A2r * (lpc_pred_t)q2r;
                    lpc_pred_t pi = (lpc_pred_t)A1i * (lpc_pred_t)q1i + (lpc_pred_t)A2i * (lpc_pred_t)q2i;

                    int rec_re = lpc_wrap_int16(dval[0] + lpc_round(pr));
                    int rec_im = lpc_wrap_int16(dval[1] + lpc_round(pi));

                    v_re[ch][s][k] = (short)rec_re;
                    v_im[ch][s][k] = (short)rec_im;

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
