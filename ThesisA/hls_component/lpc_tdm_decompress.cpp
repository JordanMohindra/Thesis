#include "lpc_tdm_decompress.h"

// ===========================================================================
//  TDM-MIMO aware LPC + Huffman decompressor, two-stage streaming version.
//
//  The first version decoded each value inside nested loops that were not
//  pipelined, and matched the Huffman code by trying the sixteen codewords one
//  after another in category order. Its speed therefore depended on the data:
//  7.6 to 8.3 clocks per value, 15.4 ms per frame on the KCU116.
//
//  This version uses the structure of the DRHE decompressor (DATAFLOW):
//
//    unpack  : reads the coefficient table (64 bits per channel and range bin),
//              then decodes one residual per clock. A 29-bit window (14-bit
//              longest code + 15 APPEND bits) is cut from two 256-bit words at
//              the current bit position and all sixteen codewords are matched
//              against it at once.
//    rebuild : one RX channel per clock. Two fixed-point multiply-accumulates
//              per value from the reconstruction ring of each (channel, bin),
//              exactly as before.
//
//  Bit order, value order and arithmetic are unchanged, so the output is
//  bit-identical to the first version. It still needs no frame buffer. A frame
//  takes about nRX x nSamples (coefficients) + 2 x nRamps x nSamples x nRX
//  (residuals) clocks: about 197,000 at 128 x 192 x 4.
// ===========================================================================

const int LPC_WIN_BITS = 29;   // 14-bit longest code + 15 APPEND bits

// Match the low bits of the window against the dictionary. The code is
// prefix-free, so exactly one entry matches.
static inline void lpc_match_code(ap_uint<14> w, ap_uint<4>& s4, ap_uint<4>& len) {
#pragma HLS INLINE
    s4 = 0;
    len = 0;
    MATCH: for (int i = 15; i >= 0; i--) {
#pragma HLS UNROLL
        ap_uint<4>  L    = LPC_TDM_HUFFMAN_TABLE[i].len;
        ap_uint<14> mask = (ap_uint<14>)((1u << L) - 1u);
        if ((w & mask) == LPC_TDM_HUFFMAN_TABLE[i].code) {
            s4  = i;
            len = L;
        }
    }
}

// Stage 1: compressed words -> coefficient words, then (re, im) residual pairs.
static void lpc_unpack(hls::stream<axis_256_t>& in_stream,
                       hls::stream<ap_uint<64> >& coefs,
                       hls::stream<ap_uint<32> >& pairs,
                       int nSamples, int nRamps, int nRX) {
    ap_uint<256> cur = 0;       // word holding the current bit position
    ap_uint<256> nxt = 0;       // the word after it, fetched just in time
    ap_uint<9>   pos = 0;       // bit position inside cur, 0..255
    bool nxt_valid = false;
    bool seen_last = false;     // TLAST word read: never read past it

    {
        axis_256_t p = in_stream.read();
        cur = p.data;
        seen_last = (p.last == 1);
    }

    // ---- coefficient table: 64 bits per (channel, range bin) ----------------
    const int nCoef = nRX * nSamples;
    COEF: for (int i = 0; i < nCoef; i++) {
#pragma HLS PIPELINE II=1
        // Blocking read bounded by TLAST (empty() is not a safe end-of-data
        // test on hardware, where words arrive from a DMA with variable delay).
        if (!nxt_valid && !seen_last && pos >= 256 - 64) {
            axis_256_t p = in_stream.read();
            nxt = p.data;
            seen_last = (p.last == 1);
            nxt_valid = true;
        }
        ap_uint<512> both = (nxt, cur);
        ap_uint<64> word = both >> pos;
        coefs.write(word);

        ap_uint<10> np = pos + 64;
        if (np >= 256) {
            cur = nxt;
            nxt = 0;
            nxt_valid = false;
            pos = np - 256;
        } else {
            pos = np;
        }
    }

    // ---- residuals, one value per clock -------------------------------------
    const int nVals = nRamps * nSamples * nRX * 2;    // re and im per channel
    ap_uint<16> held_re = 0;
    UNPACK: for (int i = 0; i < nVals; i++) {
#pragma HLS PIPELINE II=1
        if (!nxt_valid && !seen_last && pos >= 256 - LPC_WIN_BITS) {
            axis_256_t p = in_stream.read();
            nxt = p.data;
            seen_last = (p.last == 1);
            nxt_valid = true;
        }

        ap_uint<512> both = (nxt, cur);
        ap_uint<LPC_WIN_BITS> w = both >> pos;

        ap_uint<4> s4, len;
        lpc_match_code(w.range(13, 0), s4, len);

        ap_uint<15> append = (w >> len) & (ap_uint<15>)((1u << s4) - 1u);
        int diff = decode_append_bits(append, s4);

        ap_uint<10> np = pos + len + s4;
        if (np >= 256) {
            cur = nxt;
            nxt = 0;
            nxt_valid = false;
            pos = np - 256;
        } else {
            pos = np;
        }

        ap_uint<16> d16 = (ap_uint<16>)(ap_int<16>)diff;
        if ((i & 1) == 0) {
            held_re = d16;
        } else {
            pairs.write((d16, held_re));    // [31:16] = im, [15:0] = re
        }
    }
}

// Stage 2: coefficients + residual pairs -> reconstructed samples,
// one RX channel per clock.
static void lpc_rebuild(hls::stream<ap_uint<64> >& coefs,
                        hls::stream<ap_uint<32> >& pairs,
                        hls::stream<axis_128_t>& out_stream,
                        int nSamples, int nRamps, int nRX, int nTx) {
    static lpc_a1_t a1_re[LPC_MAX_NRX][LPC_MAX_N];
    static lpc_a2_t a2_re[LPC_MAX_NRX][LPC_MAX_N];
    static lpc_a1_t a1_im[LPC_MAX_NRX][LPC_MAX_N];
    static lpc_a2_t a2_im[LPC_MAX_NRX][LPC_MAX_N];
#pragma HLS ARRAY_PARTITION variable=a1_re complete dim=1
#pragma HLS ARRAY_PARTITION variable=a2_re complete dim=1
#pragma HLS ARRAY_PARTITION variable=a1_im complete dim=1
#pragma HLS ARRAY_PARTITION variable=a2_im complete dim=1
#pragma HLS BIND_STORAGE variable=a1_re type=ram_2p impl=lutram
#pragma HLS BIND_STORAGE variable=a2_re type=ram_2p impl=lutram
#pragma HLS BIND_STORAGE variable=a1_im type=ram_2p impl=lutram
#pragma HLS BIND_STORAGE variable=a2_im type=ram_2p impl=lutram

    // Reconstruction ring: [channel][range bin][ramp mod 2*nTx]
    static short v_re[LPC_MAX_NRX][LPC_MAX_N][LPC_TDM_HIST];
    static short v_im[LPC_MAX_NRX][LPC_MAX_N][LPC_TDM_HIST];
#pragma HLS ARRAY_PARTITION variable=v_re complete dim=1
#pragma HLS ARRAY_PARTITION variable=v_im complete dim=1
#pragma HLS ARRAY_PARTITION variable=v_re complete dim=3
#pragma HLS ARRAY_PARTITION variable=v_im complete dim=3
    // Small memories (128 x 16 bits each): distributed RAM, not block RAM,
    // as in the first version, which used no block RAM at all.
#pragma HLS BIND_STORAGE variable=v_re type=ram_2p impl=lutram
#pragma HLS BIND_STORAGE variable=v_im type=ram_2p impl=lutram
    // A ring slot is read again nTx ramps later (nTx x nSamples x nRX
    // iterations), far beyond the pipeline depth: no loop-carried hazard.
#pragma HLS DEPENDENCE variable=v_re inter false
#pragma HLS DEPENDENCE variable=v_im inter false

    // ---- coefficient table, same order as the compressor wrote it -----------
    int cch = 0, cn = 0;
    const int nCoef = nRX * nSamples;
    COEF_IN: for (int i = 0; i < nCoef; i++) {
#pragma HLS PIPELINE II=1
        ap_uint<64> word = coefs.read();
        a1_re[cch][cn] = lpc_unpack_a1((ap_uint<16>)(word.range(15, 0)));
        a2_re[cch][cn] = lpc_unpack_a2((ap_uint<16>)(word.range(31, 16)));
        a1_im[cch][cn] = lpc_unpack_a1((ap_uint<16>)(word.range(47, 32)));
        a2_im[cch][cn] = lpc_unpack_a2((ap_uint<16>)(word.range(63, 48)));
        if (cn == nSamples - 1) { cn = 0; cch++; } else { cn++; }
    }

    // ---- residuals, in the raster order the samples had ---------------------
    // The first version cleared the ring before each frame. Reading zero for a
    // lag that does not exist yet (r < nTx for lag nTx, r < 2*nTx for lag
    // 2*nTx) gives the same values without the clearing loop.
    const int HIST = 2 * nTx;
    int ch = 0, s = 0, r = 0, k = 0, k1 = nTx;   // k = r mod 2nTx, k1 = (r + nTx) mod 2nTx
    ap_uint<128> raw_out = 0;
    const int total = nRamps * nSamples * nRX;

    REBUILD: for (int i = 0; i < total; i++) {
#pragma HLS PIPELINE II=1
        ap_uint<32> p = pairs.read();
        int dre = (int)(ap_int<16>)p.range(15, 0);
        int dim = (int)(ap_int<16>)p.range(31, 16);

        lpc_a1_t A1r = a1_re[ch][s], A1i = a1_im[ch][s];
        lpc_a2_t A2r = a2_re[ch][s], A2i = a2_im[ch][s];

        bool have1 = (r >= nTx);        // ramp r - nTx exists
        bool have2 = (r >= HIST);       // ramp r - 2nTx exists
        int q1r = have1 ? (int)v_re[ch][s][k1] : 0;
        int q2r = have2 ? (int)v_re[ch][s][k]  : 0;
        int q1i = have1 ? (int)v_im[ch][s][k1] : 0;
        int q2i = have2 ? (int)v_im[ch][s][k]  : 0;

        lpc_pred_t pr = (lpc_pred_t)A1r * (lpc_pred_t)q1r + (lpc_pred_t)A2r * (lpc_pred_t)q2r;
        lpc_pred_t pi = (lpc_pred_t)A1i * (lpc_pred_t)q1i + (lpc_pred_t)A2i * (lpc_pred_t)q2i;

        int rec_re = lpc_wrap_int16(dre + lpc_round(pr));
        int rec_im = lpc_wrap_int16(dim + lpc_round(pi));

        v_re[ch][s][k] = (short)rec_re;
        v_im[ch][s][k] = (short)rec_im;

        ap_uint<32> w;
        w.range(15, 0)  = (ap_uint<16>)(ap_int<16>)rec_re;
        w.range(31, 16) = (ap_uint<16>)(ap_int<16>)rec_im;
        raw_out.range(ch * 32 + 31, ch * 32) = w;

        if (ch == nRX - 1) {
            axis_128_t out_pkt;
            out_pkt.data = raw_out;
            out_pkt.last = (r == nRamps - 1 && s == nSamples - 1) ? 1 : 0;
            out_pkt.keep = -1;
            out_stream.write(out_pkt);
            raw_out = 0;
        }

        // advance (ch, s, r) and the ring indices
        if (ch == nRX - 1) {
            ch = 0;
            if (s == nSamples - 1) {
                s = 0;
                r++;
                k  = (k  == HIST - 1) ? 0 : k  + 1;
                k1 = (k1 == HIST - 1) ? 0 : k1 + 1;
            } else {
                s++;
            }
        } else {
            ch++;
        }
    }
}

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
#pragma HLS DATAFLOW

    hls::stream<ap_uint<64> > coefs("coefs");
#pragma HLS STREAM variable=coefs depth=8
    hls::stream<ap_uint<32> > pairs("pairs");
#pragma HLS STREAM variable=pairs depth=64

    lpc_unpack(in_stream, coefs, pairs, nSamples, nRamps, nRX);
    lpc_rebuild(coefs, pairs, out_stream, nSamples, nRamps, nRX, nTx);
}
