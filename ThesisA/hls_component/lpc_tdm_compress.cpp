#include "lpc_tdm_compress.h"

// ===========================================================================
//  TDM-MIMO aware LPC + Huffman compressor.
//
//  Model:  x_hat[m] = a1*x[m-nTx] + a2*x[m-2*nTx]
//
//  Bitstream layout is byte-for-byte the same shape as the baseline:
//    [coefficients]  for ch, for n:  a1_re | a2_re | a1_im | a2_im  (4 x 16b)
//    [residuals]     for r, for s, for ch:  enc(d_re) | enc(d_im)
//
//  History ring
//  ------------
//  Both the autocorrelation pass and the residual pass need x[m-nTx] and
//  x[m-2*nTx]. A ring of exactly 2*nTx entries gives both for free: at ramp m,
//  slot k = m mod 2nTx still holds the value from ramp m-2nTx (it is about to
//  be overwritten), and slot (k+nTx) mod 2nTx holds the value from m-nTx.
//  No shifting is needed, so the ring costs 2*nTx registers and two muxes.
// ===========================================================================

void lpc_tdm_compress(
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

    // Whole frame: samples on the way in, residuals on the way out.
    static ap_uint<32> frame_buf[LPC_MAX_NRX][LPC_MAX_RAMPS][LPC_MAX_N];
#pragma HLS ARRAY_PARTITION variable=frame_buf complete dim=1

    static lpc_a1_t a1_re[LPC_MAX_NRX][LPC_MAX_N];
    static lpc_a2_t a2_re[LPC_MAX_NRX][LPC_MAX_N];
    static lpc_a1_t a1_im[LPC_MAX_NRX][LPC_MAX_N];
    static lpc_a2_t a2_im[LPC_MAX_NRX][LPC_MAX_N];
#pragma HLS ARRAY_PARTITION variable=a1_re complete dim=1
#pragma HLS ARRAY_PARTITION variable=a2_re complete dim=1
#pragma HLS ARRAY_PARTITION variable=a1_im complete dim=1
#pragma HLS ARRAY_PARTITION variable=a2_im complete dim=1

    const int HIST = 2 * nTx;

    // =======================================================================
    //  PASS 1 - buffer the frame. Pure streaming write, II=1.
    // =======================================================================
    INGEST_RAMP: for (int r = 0; r < nRamps; r++) {
        INGEST_SAMPLE: for (int s = 0; s < nSamples; s++) {
#pragma HLS PIPELINE II=1
            axis_128_t in_pkt = in_stream.read();
            ap_uint<128> raw = in_pkt.data;
            INGEST_CH: for (int ch = 0; ch < LPC_MAX_NRX; ch++) {
#pragma HLS UNROLL
                if (ch < nRX) {
                    frame_buf[ch][r][s] = raw.range((ch + 1) * 32 - 1, ch * 32);
                }
            }
        }
    }

    // =======================================================================
    //  PASS 2 - per (channel, range bin): correlate at lags nTx and 2*nTx,
    //  solve, then rewrite the buffered samples in place as residuals.
    // =======================================================================
    SOLVE_CH: for (int ch = 0; ch < LPC_MAX_NRX; ch++) {
        if (ch >= nRX) continue;
        SOLVE_BIN: for (int n = 0; n < nSamples; n++) {

            ap_int<64> R0r = 0, R1r = 0, R2r = 0;
            ap_int<64> R0i = 0, R1i = 0, R2i = 0;

            int hr[LPC_TDM_HIST];
            int hi[LPC_TDM_HIST];
#pragma HLS ARRAY_PARTITION variable=hr complete dim=1
#pragma HLS ARRAY_PARTITION variable=hi complete dim=1
            INIT_HIST: for (int k = 0; k < LPC_TDM_HIST; k++) {
#pragma HLS UNROLL
                hr[k] = 0; hi[k] = 0;
            }

            CORR_RAMP: for (int m = 0; m < nRamps; m++) {
#pragma HLS PIPELINE II=1
                ap_uint<32> w = frame_buf[ch][m][n];
                ap_int<16> re_raw = w.range(15, 0);
                ap_int<16> im_raw = w.range(31, 16);
                int re = (int)re_raw;
                int im = (int)im_raw;

                int k  = m % HIST;
                int k1 = (k + nTx) % HIST;   // value from ramp m - nTx
                int q1r = hr[k1], q1i = hi[k1];
                int q2r = hr[k],  q2i = hi[k];   // value from ramp m - 2*nTx

                R0r += (ap_int<64>)re * re;
                R0i += (ap_int<64>)im * im;
                if (m >= nTx) {
                    R1r += (ap_int<64>)re * q1r;
                    R1i += (ap_int<64>)im * q1i;
                }
                if (m >= HIST) {
                    R2r += (ap_int<64>)re * q2r;
                    R2i += (ap_int<64>)im * q2i;
                }

                hr[k] = re; hi[k] = im;
            }

            lpc_a1_t A1r, A1i;
            lpc_a2_t A2r, A2i;
            lpc_solve_order2(R0r, R1r, R2r, A1r, A2r);
            lpc_solve_order2(R0i, R1i, R2i, A1i, A2i);
            a1_re[ch][n] = A1r; a2_re[ch][n] = A2r;
            a1_im[ch][n] = A1i; a2_im[ch][n] = A2i;

            int vr[LPC_TDM_HIST];
            int vi[LPC_TDM_HIST];
#pragma HLS ARRAY_PARTITION variable=vr complete dim=1
#pragma HLS ARRAY_PARTITION variable=vi complete dim=1
            INIT_REC: for (int k = 0; k < LPC_TDM_HIST; k++) {
#pragma HLS UNROLL
                vr[k] = 0; vi[k] = 0;
            }

            RESIDUAL_RAMP: for (int m = 0; m < nRamps; m++) {
#pragma HLS PIPELINE II=1
                ap_uint<32> w = frame_buf[ch][m][n];
                ap_int<16> re_raw = w.range(15, 0);
                ap_int<16> im_raw = w.range(31, 16);
                int re = (int)re_raw;
                int im = (int)im_raw;

                int k  = m % HIST;
                int k1 = (k + nTx) % HIST;
                int v1r = vr[k1], v1i = vi[k1];
                int v2r = vr[k],  v2i = vi[k];

                lpc_pred_t pr = (lpc_pred_t)A1r * (lpc_pred_t)v1r + (lpc_pred_t)A2r * (lpc_pred_t)v2r;
                lpc_pred_t pi = (lpc_pred_t)A1i * (lpc_pred_t)v1i + (lpc_pred_t)A2i * (lpc_pred_t)v2i;
                int pred_re = lpc_round(pr);
                int pred_im = lpc_round(pi);

                int d_re = lpc_wrap_int16(re - pred_re);
                int d_im = lpc_wrap_int16(im - pred_im);
                if (d_re == -32768) d_re = -32767;
                if (d_im == -32768) d_im = -32767;

                int rec_re = lpc_wrap_int16(d_re + pred_re);
                int rec_im = lpc_wrap_int16(d_im + pred_im);

                ap_uint<32> dw = 0;
                dw.range(15, 0)  = (ap_uint<16>)(ap_int<16>)d_re;
                dw.range(31, 16) = (ap_uint<16>)(ap_int<16>)d_im;
                frame_buf[ch][m][n] = dw;

                vr[k] = rec_re; vi[k] = rec_im;
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
