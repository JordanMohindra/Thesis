#include "lpc_compress.h"

// ===========================================================================
//  LPC + Huffman compressor.
//
//  Bitstream layout (LSB-first within each 256-bit AXI word, matching DRHE):
//
//    [coefficients]  for ch, for n:  a1_re | a2_re | a1_im | a2_im   (4 x 16b)
//    [residuals]     for r, for s, for ch:  enc(d_re) | enc(d_im)
//
//  Coefficients come first because the decompressor needs all of them before
//  it can reconstruct any sample. Residuals are emitted in the SAME raster
//  order the samples arrived in, which is what lets the decompressor stream:
//  it reconstructs each sample as the residual arrives and never buffers a
//  frame. The reordering cost is paid once, here, by the compressor that
//  already had to buffer.
// ===========================================================================

void lpc_compress(
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

    // ---- Frame buffer -----------------------------------------------------
    //  Holds the whole frame: samples on the way in, residuals on the way out
    //  (rewritten in place). 4 x 192 x 128 x 32 bits = 3.1 Mbit.
    static ap_uint<32> frame_buf[LPC_MAX_NRX][LPC_MAX_RAMPS][LPC_MAX_N];
#pragma HLS ARRAY_PARTITION variable=frame_buf complete dim=1

    // ---- Autocorrelation accumulators, exact in 64-bit integer ------------
    static ap_int<64> R0_re[LPC_MAX_NRX][LPC_MAX_N];
    static ap_int<64> R1_re[LPC_MAX_NRX][LPC_MAX_N];
    static ap_int<64> R2_re[LPC_MAX_NRX][LPC_MAX_N];
    static ap_int<64> R0_im[LPC_MAX_NRX][LPC_MAX_N];
    static ap_int<64> R1_im[LPC_MAX_NRX][LPC_MAX_N];
    static ap_int<64> R2_im[LPC_MAX_NRX][LPC_MAX_N];
#pragma HLS ARRAY_PARTITION variable=R0_re complete dim=1
#pragma HLS ARRAY_PARTITION variable=R1_re complete dim=1
#pragma HLS ARRAY_PARTITION variable=R2_re complete dim=1
#pragma HLS ARRAY_PARTITION variable=R0_im complete dim=1
#pragma HLS ARRAY_PARTITION variable=R1_im complete dim=1
#pragma HLS ARRAY_PARTITION variable=R2_im complete dim=1

    // Running history used only while accumulating the correlations.
    static short p1_re[LPC_MAX_NRX][LPC_MAX_N];
    static short p2_re[LPC_MAX_NRX][LPC_MAX_N];
    static short p1_im[LPC_MAX_NRX][LPC_MAX_N];
    static short p2_im[LPC_MAX_NRX][LPC_MAX_N];
#pragma HLS ARRAY_PARTITION variable=p1_re complete dim=1
#pragma HLS ARRAY_PARTITION variable=p2_re complete dim=1
#pragma HLS ARRAY_PARTITION variable=p1_im complete dim=1
#pragma HLS ARRAY_PARTITION variable=p2_im complete dim=1

    // ---- Solved coefficients ---------------------------------------------
    static lpc_a1_t a1_re[LPC_MAX_NRX][LPC_MAX_N];
    static lpc_a2_t a2_re[LPC_MAX_NRX][LPC_MAX_N];
    static lpc_a1_t a1_im[LPC_MAX_NRX][LPC_MAX_N];
    static lpc_a2_t a2_im[LPC_MAX_NRX][LPC_MAX_N];
#pragma HLS ARRAY_PARTITION variable=a1_re complete dim=1
#pragma HLS ARRAY_PARTITION variable=a2_re complete dim=1
#pragma HLS ARRAY_PARTITION variable=a1_im complete dim=1
#pragma HLS ARRAY_PARTITION variable=a2_im complete dim=1

    // =======================================================================
    //  PASS 1 - ingest the frame, buffer it, and accumulate R0/R1/R2.
    // =======================================================================
    INGEST_RAMP: for (int r = 0; r < nRamps; r++) {
        INGEST_SAMPLE: for (int s = 0; s < nSamples; s++) {
#pragma HLS PIPELINE II=1
            axis_128_t in_pkt = in_stream.read();
            ap_uint<128> raw = in_pkt.data;

            INGEST_CH: for (int ch = 0; ch < LPC_MAX_NRX; ch++) {
#pragma HLS UNROLL
                if (ch < nRX) {
                    if (r == 0) {
                        R0_re[ch][s] = 0; R1_re[ch][s] = 0; R2_re[ch][s] = 0;
                        R0_im[ch][s] = 0; R1_im[ch][s] = 0; R2_im[ch][s] = 0;
                        p1_re[ch][s] = 0; p2_re[ch][s] = 0;
                        p1_im[ch][s] = 0; p2_im[ch][s] = 0;
                    }

                    ap_uint<32> w = raw.range((ch + 1) * 32 - 1, ch * 32);
                    ap_int<16> re_raw = w.range(15, 0);
                    ap_int<16> im_raw = w.range(31, 16);
                    int re = (int)re_raw;
                    int im = (int)im_raw;

                    frame_buf[ch][r][s] = w;

                    int q1r = (int)p1_re[ch][s], q2r = (int)p2_re[ch][s];
                    int q1i = (int)p1_im[ch][s], q2i = (int)p2_im[ch][s];

                    R0_re[ch][s] += (ap_int<64>)re * re;
                    R0_im[ch][s] += (ap_int<64>)im * im;
                    if (r >= 1) {
                        R1_re[ch][s] += (ap_int<64>)re * q1r;
                        R1_im[ch][s] += (ap_int<64>)im * q1i;
                    }
                    if (r >= 2) {
                        R2_re[ch][s] += (ap_int<64>)re * q2r;
                        R2_im[ch][s] += (ap_int<64>)im * q2i;
                    }

                    p2_re[ch][s] = (short)q1r; p1_re[ch][s] = (short)re;
                    p2_im[ch][s] = (short)q1i; p1_im[ch][s] = (short)im;
                }
            }
        }
    }

    // =======================================================================
    //  PASS 2 - solve per (channel, range bin), then rewrite the buffered
    //  samples in place as residuals.
    // =======================================================================
    SOLVE_CH: for (int ch = 0; ch < LPC_MAX_NRX; ch++) {
        if (ch >= nRX) continue;
        SOLVE_BIN: for (int n = 0; n < nSamples; n++) {
            lpc_a1_t A1r, A1i;
            lpc_a2_t A2r, A2i;
            lpc_solve_order2(R0_re[ch][n], R1_re[ch][n], R2_re[ch][n], A1r, A2r);
            lpc_solve_order2(R0_im[ch][n], R1_im[ch][n], R2_im[ch][n], A1i, A2i);
            a1_re[ch][n] = A1r; a2_re[ch][n] = A2r;
            a1_im[ch][n] = A1i; a2_im[ch][n] = A2i;

            int v1r = 0, v2r = 0, v1i = 0, v2i = 0;

            RESIDUAL_RAMP: for (int m = 0; m < nRamps; m++) {
#pragma HLS PIPELINE II=1
                ap_uint<32> w = frame_buf[ch][m][n];
                ap_int<16> re_raw = w.range(15, 0);
                ap_int<16> im_raw = w.range(31, 16);
                int re = (int)re_raw;
                int im = (int)im_raw;

                lpc_pred_t pr = (lpc_pred_t)A1r * (lpc_pred_t)v1r + (lpc_pred_t)A2r * (lpc_pred_t)v2r;
                lpc_pred_t pi = (lpc_pred_t)A1i * (lpc_pred_t)v1i + (lpc_pred_t)A2i * (lpc_pred_t)v2i;
                int pred_re = lpc_round(pr);
                int pred_im = lpc_round(pi);

                int d_re = lpc_wrap_int16(re - pred_re);
                int d_im = lpc_wrap_int16(im - pred_im);

                // The S4/APPEND code cannot represent -32768 (region 15 spans
                // exactly 2^15 values), so clamp it, exactly as DRHE does.
                if (d_re == -32768) d_re = -32767;
                if (d_im == -32768) d_im = -32767;

                // Closed loop: carry forward what the decompressor will
                // reconstruct, not the original sample, so a clamp cannot
                // desynchronise the two predictors.
                int rec_re = lpc_wrap_int16(d_re + pred_re);
                int rec_im = lpc_wrap_int16(d_im + pred_im);

                ap_uint<32> dw = 0;
                dw.range(15, 0)  = (ap_uint<16>)(ap_int<16>)d_re;
                dw.range(31, 16) = (ap_uint<16>)(ap_int<16>)d_im;
                frame_buf[ch][m][n] = dw;

                v2r = v1r; v1r = rec_re;
                v2i = v1i; v1i = rec_im;
            }
        }
    }

    // =======================================================================
    //  PASS 3 - emit coefficients, then the residuals in raster order.
    // =======================================================================
    ap_uint<512> bit_buffer = 0;
    int bit_count = 0;

    EMIT_COEF_CH: for (int ch = 0; ch < LPC_MAX_NRX; ch++) {
        if (ch >= nRX) continue;
        EMIT_COEF_BIN: for (int n = 0; n < nSamples; n++) {
#pragma HLS PIPELINE II=1
            ap_uint<16> c0 = lpc_pack_a1(a1_re[ch][n]);
            ap_uint<16> c1 = lpc_pack_a2(a2_re[ch][n]);
            ap_uint<16> c2 = lpc_pack_a1(a1_im[ch][n]);
            ap_uint<16> c3 = lpc_pack_a2(a2_im[ch][n]);

            ap_uint<64> word = ((ap_uint<64>)c3 << 48) | ((ap_uint<64>)c2 << 32)
                             | ((ap_uint<64>)c1 << 16) |  (ap_uint<64>)c0;

            bit_buffer |= ((ap_uint<512>)word << bit_count);
            bit_count += 64;

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

    EMIT_RAMP: for (int r = 0; r < nRamps; r++) {
        EMIT_SAMPLE: for (int s = 0; s < nSamples; s++) {
#pragma HLS PIPELINE II=1
            EMIT_CH: for (int ch = 0; ch < LPC_MAX_NRX; ch++) {
#pragma HLS UNROLL
                if (ch < nRX) {
                    ap_uint<32> dw = frame_buf[ch][r][s];
                    ap_int<16> dre = dw.range(15, 0);
                    ap_int<16> dim = dw.range(31, 16);

                    ap_uint<4>  s4_re = get_s4_region((int)dre);
                    ap_uint<15> ap_re = get_append_bits((int)dre, s4_re);
                    DictEntry_t h_re = HUFFMAN_TABLE[s4_re];

                    ap_uint<4>  s4_im = get_s4_region((int)dim);
                    ap_uint<15> ap_im = get_append_bits((int)dim, s4_im);
                    DictEntry_t h_im = HUFFMAN_TABLE[s4_im];

                    ap_uint<32> code_re = ((ap_uint<32>)ap_re << h_re.len) | (ap_uint<32>)h_re.code;
                    ap_uint<32> code_im = ((ap_uint<32>)ap_im << h_im.len) | (ap_uint<32>)h_im.code;

                    bit_buffer |= ((ap_uint<512>)code_re << bit_count);
                    bit_count += h_re.len + s4_re;
                    bit_buffer |= ((ap_uint<512>)code_im << bit_count);
                    bit_count += h_im.len + s4_im;
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
    }

    if (bit_count > 0) {
        axis_256_t out_pkt;
        out_pkt.data = bit_buffer.range(255, 0);
        out_pkt.last = 1;
        out_pkt.keep = -1;
        out_stream.write(out_pkt);
    }
}
