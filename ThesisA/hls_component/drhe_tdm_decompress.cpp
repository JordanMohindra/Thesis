#include "drhe_tdm_decompress.h"
#include <cmath>

// ---------------------------------------------------------------------------
// DRHE (lag nTx) decompressor, area-optimised so it fits on the XCKU5P next to
// the compressor.
//
// The first version decoded all 8 values of a sample (4 RX x re/im) in one
// pipeline iteration: eight Huffman decodes and eight variable shifts of a
// 512-bit buffer chained in series, plus four copies of the float predictor.
// That synthesised to about 182,000 LUTs. This version splits the work into two
// stages that run concurrently (DATAFLOW):
//
//   unpack  : one value per clock. A 29-bit window (the longest value is a
//             14-bit code + 15 APPEND bits) is cut from two 256-bit words at
//             the current bit position, the Huffman code is matched against the
//             16-entry dictionary in parallel, and the position advances by
//             code length + S4. Values are paired (re, im) and passed on.
//   rebuild : one RX channel per clock. The same float predictor as the
//             compressor (identical expressions, so identical rounding),
//             one copy instead of four, state held in BRAM.
//
// Bit order, value order and the predictor are unchanged, so the output is
// bit-identical to the previous decompressor. A frame takes about
// 2 x nSamples x nRamps x nRX clocks (196,608 at 128 x 192 x 4).
// ---------------------------------------------------------------------------

static inline int wrap_int16(int val) {
    return ((val + 32768) & 0xFFFF) - 32768;
}

const int WIN_BITS = 29;   // 14-bit longest code + 15 APPEND bits

// Match the low bits of the window against the dictionary. The code is
// prefix-free, so exactly one entry matches.
static inline void match_code(ap_uint<14> w, ap_uint<4>& s4, ap_uint<4>& len) {
#pragma HLS INLINE
    s4 = 0;
    len = 0;
    MATCH: for (int i = 15; i >= 0; i--) {
#pragma HLS UNROLL
        ap_uint<4>  L    = DRHE_TDM_HUFFMAN_TABLE[i].len;
        ap_uint<14> mask = (ap_uint<14>)((1u << L) - 1u);
        if ((w & mask) == DRHE_TDM_HUFFMAN_TABLE[i].code) {
            s4  = i;
            len = L;
        }
    }
}

// Stage 1: compressed words -> (re, im) residual pairs, one value per clock.
static void unpack(hls::stream<axis_256_t>& in_stream,
                   hls::stream<ap_uint<32> >& pairs,
                   int nSamples, int nRamps, int nRX) {
    const int nVals = nRamps * nSamples * nRX * 2;    // re and im per channel
    ap_uint<256> cur = 0;       // word holding the current bit position
    ap_uint<256> nxt = 0;       // the word after it, fetched just in time
    ap_uint<9>   pos = 0;       // bit position inside cur, 0..255
    bool nxt_valid = false;
    bool seen_last = false;     // TLAST word read: never read past it
    ap_uint<16> held_re = 0;

    {
        axis_256_t p = in_stream.read();
        cur = p.data;
        seen_last = (p.last == 1);
    }

    UNPACK: for (int i = 0; i < nVals; i++) {
#pragma HLS PIPELINE II=1
        // Fetch the next word once the window can reach past this one.
        // Blocking read, bounded by TLAST (see the note in the compressor's
        // board history: empty() is not a safe end-of-data test on hardware).
        if (!nxt_valid && !seen_last && pos > 256 - WIN_BITS) {
            axis_256_t p = in_stream.read();
            nxt = p.data;
            seen_last = (p.last == 1);
            nxt_valid = true;
        }

        ap_uint<512> both = (nxt, cur);
        ap_uint<WIN_BITS> w = both >> pos;

        ap_uint<4> s4, len;
        match_code(w.range(13, 0), s4, len);

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

// Stage 2: residual pairs -> reconstructed samples, one RX channel per clock.
static void rebuild(hls::stream<ap_uint<32> >& pairs,
                    hls::stream<axis_128_t>& out_stream,
                    int nSamples, int nRamps, int nRX, int nTx) {
    // One predictor history per (channel, transmitter, range bin).
    static float s_mag_pred[MAX_NRX * TDM_STATE_SIZE];
    static float s_prev_mag[MAX_NRX * TDM_STATE_SIZE];
    static float s_phase_pred[MAX_NRX * TDM_STATE_SIZE];
    static float s_prev_phase[MAX_NRX * TDM_STATE_SIZE];
    static float s_prev_prev_phase[MAX_NRX * TDM_STATE_SIZE];
    // A slot is revisited nTx ramps later (nTx x nSamples x nRX iterations),
    // far beyond the pipeline depth, so there is no loop-carried hazard.
#pragma HLS DEPENDENCE variable=s_mag_pred inter false
#pragma HLS DEPENDENCE variable=s_prev_mag inter false
#pragma HLS DEPENDENCE variable=s_phase_pred inter false
#pragma HLS DEPENDENCE variable=s_prev_phase inter false
#pragma HLS DEPENDENCE variable=s_prev_prev_phase inter false

    int ch = 0, s = 0, r = 0, tx = 0;
    ap_uint<128> restored_raw = 0;
    const int total = nRamps * nSamples * nRX;

    REBUILD: for (int i = 0; i < total; i++) {
#pragma HLS PIPELINE II=1
        ap_uint<32> p = pairs.read();
        int diff_re = (int)(ap_int<16>)p.range(15, 0);
        int diff_im = (int)(ap_int<16>)p.range(31, 16);

        int idx = ch * TDM_STATE_SIZE + tdm_state_index(tx, s);

        // Each transmitter's history starts on its own first ramp (r < nTx).
        bool fresh = (r < nTx);
        float st_mag_pred   = fresh ? 0.0f : s_mag_pred[idx];
        float st_prev_mag   = fresh ? 0.0f : s_prev_mag[idx];
        float st_phase_pred = fresh ? 0.0f : s_phase_pred[idx];
        float st_prev_phase = fresh ? 0.0f : s_prev_phase[idx];
        float st_prev_prev  = fresh ? 0.0f : s_prev_prev_phase[idx];

        // Same expressions as the compressor, so the rounding is identical.
        float mag_pred   = ALPHA * st_mag_pred + (1.0f - ALPHA) * st_prev_mag;
        float phase_pred = BETA * st_phase_pred + (2.0f - BETA) * st_prev_phase - st_prev_prev;

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

        s_prev_prev_phase[idx] = st_prev_phase;
        s_prev_phase[idx]      = curr_phase;
        s_phase_pred[idx]      = phase_pred;
        s_prev_mag[idx]        = curr_mag;
        s_mag_pred[idx]        = mag_pred;

        ap_uint<32> ch_out;
        ch_out.range(15, 0)  = (ap_uint<16>)(ap_int<16>)re;
        ch_out.range(31, 16) = (ap_uint<16>)(ap_int<16>)im;
        restored_raw.range(ch * 32 + 31, ch * 32) = ch_out;

        if (ch == nRX - 1) {
            axis_128_t out_pkt;
            out_pkt.data = restored_raw;
            out_pkt.last = (r == nRamps - 1 && s == nSamples - 1) ? 1 : 0;
            out_pkt.keep = -1;
            out_stream.write(out_pkt);
            restored_raw = 0;
        }

        // advance (ch, s, r, tx)
        if (ch == nRX - 1) {
            ch = 0;
            if (s == nSamples - 1) {
                s = 0;
                r++;
                tx = (tx == nTx - 1) ? 0 : tx + 1;
            } else {
                s++;
            }
        } else {
            ch++;
        }
    }
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
#pragma HLS DATAFLOW

    hls::stream<ap_uint<32> > pairs("pairs");
#pragma HLS STREAM variable=pairs depth=64

    unpack(in_stream, pairs, nSamples, nRamps, nRX);
    rebuild(pairs, out_stream, nSamples, nRamps, nRX, nTx);
}
