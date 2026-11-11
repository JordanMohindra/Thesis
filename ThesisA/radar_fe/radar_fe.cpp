// =============================================================================
//  radar_fe.cpp - range-FFT front end for the KCU116 test system
//
//  Raw ADC ramps (4 RX, complex int16) in; FX16 range bins out, computed as the
//  MATLAB chain does (loadColoRadarFrame + preprocessing + rangeFFT +
//  compress_fx16):
//      code[k] = int16(round( FFT(w .* (x - mean(x)))[k] / 63.75 )),  k < 128
//  w is the symmetric 256-point Hann window, mean(x) the mean of the ramp.
//
//  Architecture: a dataflow chain of 10 processes, each handling one ramp at a
//  time, so ramps flow through it at one ramp per ~256 clocks:
//    fe_window   reads the 256 samples, applies the window, sums the ramp
//    fe_stage<s> 8 radix-2 decimation-in-frequency stages (one per process)
//    fe_out      removes the ramp mean, puts the bins in natural order,
//                scales by 1/63.75, rounds and saturates to int16
//  The mean is removed after the FFT: FFT(w(x - m)) = FFT(w x) - m * FFT(w),
//  which is exact and avoids buffering a ramp before windowing it.
// =============================================================================
#include "radar_fe.h"
#include "radar_fe_tables.h"

// ---------------------------------------------------------------- window ----
static void fe_window(hls::stream<fe_axis_t>& in, hls::stream<fe_pair>& out,
                      hls::stream<fe_mean>& mout, int nRamps) {
    RAMP: for (int r = 0; r < nRamps; r++) {
        ap_int<25> sr[FE_NRX], si[FE_NRX];
#pragma HLS ARRAY_PARTITION variable=sr complete
#pragma HLS ARRAY_PARTITION variable=si complete
        for (int c = 0; c < FE_NRX; c++) {
#pragma HLS UNROLL
            sr[c] = 0; si[c] = 0;
        }
        fe_pair p;
        SAMPLE: for (int n = 0; n < FE_N; n++) {
#pragma HLS PIPELINE II=1
            fe_axis_t beat = in.read();
            win_t w = HANN[n];
            for (int c = 0; c < FE_NRX; c++) {
#pragma HLS UNROLL
                ap_int<16> xr = beat.data.range(32 * c + 15, 32 * c);
                ap_int<16> xi = beat.data.range(32 * c + 31, 32 * c + 16);
                sr[c] += xr;
                si[c] += xi;
                fe_cx v;
                v.re = w * xr;
                v.im = w * xi;
                if (n & 1) p.b[c] = v; else p.a[c] = v;
            }
            if (n & 1) out.write(p);           // samples (2j, 2j+1) as one pair
        }
        fe_mean m;
        for (int c = 0; c < FE_NRX; c++) {
#pragma HLS UNROLL
            ap_fixed<25, 17> mr, mi;           // sum / 256, exact
            mr.range(24, 0) = sr[c].range(24, 0);
            mi.range(24, 0) = si[c].range(24, 0);
            m.re[c] = mr;
            m.im[c] = mi;
        }
        mout.write(m);
    }
}

// --------------------------------------------------------- radix-2 stage ----
// Decimation in frequency, stage S of 8: butterflies on points i0 and
// i0 + HALF, HALF = 128 >> S; the difference is multiplied by W^(pos << S).
// Pair j arrives in the previous stage's butterfly order (stage 0: natural
// order, samples 2j and 2j+1) and leaves in this stage's order.
template <int S>
static void fe_stage(hls::stream<fe_pair>& in, hls::stream<fe_pair>& out, int nRamps) {
    const int HALF = 128 >> S;
    fe_cx buf[FE_NRX][FE_N];
#pragma HLS ARRAY_PARTITION variable=buf complete dim=1
    RAMP: for (int r = 0; r < nRamps; r++) {
        STORE: for (int j = 0; j < 128; j++) {
#pragma HLS PIPELINE II=1
            fe_pair p = in.read();
            int i0, i1;
            if (S == 0) {
                i0 = 2 * j; i1 = 2 * j + 1;
            } else {
                const int PS = (S == 0) ? 0 : S - 1;   // previous stage
                const int PH = 128 >> PS;
                int g = j >> (7 - PS), pos = j & (PH - 1);
                i0 = (g << (8 - PS)) + pos; i1 = i0 + PH;
            }
            for (int c = 0; c < FE_NRX; c++) {
#pragma HLS UNROLL
                buf[c][i0] = p.a[c];
                buf[c][i1] = p.b[c];
            }
        }
        BUTTERFLY: for (int j = 0; j < 128; j++) {
#pragma HLS PIPELINE II=1
            int g = j >> (7 - S), pos = j & (HALF - 1);
            int i0 = (g << (8 - S)) + pos, i1 = i0 + HALF;
            int k = pos << S;
            tw_t wc = TWC[k], ws = TWS[k];
            fe_pair q;
            for (int c = 0; c < FE_NRX; c++) {
#pragma HLS UNROLL
                fe_cx a = buf[c][i0], b = buf[c][i1];
                fx_t dr = a.re - b.re, di = a.im - b.im;
                q.a[c].re = a.re + b.re;
                q.a[c].im = a.im + b.im;
                // (dr + j di) * (wc - j ws)
                q.b[c].re = dr * wc + di * ws;
                q.b[c].im = di * wc - dr * ws;
            }
            out.write(q);
        }
    }
}

static ap_uint<7> bitrev7(ap_uint<7> j) {
#pragma HLS INLINE
    ap_uint<7> r;
    for (int b = 0; b < 7; b++) {
#pragma HLS UNROLL
        r[6 - b] = j[b];
    }
    return r;
}

// ---------------------------------------------------------------- output ----
// After stage 7, pair j holds the points 2j and 2j+1 of the bit-reversed
// spectrum: X[bitrev7(j)] (a bin below 128) and X[bitrev7(j) + 128] (dropped).
static void fe_out(hls::stream<fe_pair>& in, hls::stream<fe_mean>& min,
                   hls::stream<fe_axis_t>& out, int nRamps) {
    const ap_ufixed<40, -5> KQ = 4.0 / 255.0;        // 1 / 63.75
    fe_cx xb[FE_NRX][FE_NB];
#pragma HLS ARRAY_PARTITION variable=xb complete dim=1
    RAMP: for (int r = 0; r < nRamps; r++) {
        fe_mean m = min.read();
        REORDER: for (int j = 0; j < 128; j++) {
#pragma HLS PIPELINE II=1
            fe_pair p = in.read();
            ap_uint<7> k = bitrev7(j);
            for (int c = 0; c < FE_NRX; c++) {
#pragma HLS UNROLL
                xb[c][k] = p.a[c];
            }
        }
        EMIT: for (int k = 0; k < FE_NB; k++) {
#pragma HLS PIPELINE II=1
            wh_t hr = WHR[k], hi = WHI[k];
            ap_uint<128> d;
            for (int c = 0; c < FE_NRX; c++) {
#pragma HLS UNROLL
                fe_cx x = xb[c][k];
                // remove the ramp mean: X - m * FFT(w)[k]
                fx_t cr = x.re - (m.re[c] * hr - m.im[c] * hi);
                fx_t ci = x.im - (m.re[c] * hi + m.im[c] * hr);
                code_t qr = cr * KQ;
                code_t qi = ci * KQ;
                d.range(32 * c + 15, 32 * c)      = qr.range(15, 0);
                d.range(32 * c + 31, 32 * c + 16) = qi.range(15, 0);
            }
            fe_axis_t beat;
            beat.data = d;
            beat.keep = -1;
            beat.strb = -1;
            beat.last = (r == nRamps - 1) && (k == FE_NB - 1);
            out.write(beat);
        }
    }
}

// ------------------------------------------------------------------- top ----
void radar_fe(hls::stream<fe_axis_t>& in_stream,
              hls::stream<fe_axis_t>& out_stream,
              int nRamps) {
#pragma HLS INTERFACE axis port=in_stream
#pragma HLS INTERFACE axis port=out_stream
#pragma HLS INTERFACE s_axilite port=nRamps bundle=control
#pragma HLS INTERFACE s_axilite port=return bundle=control
#pragma HLS DATAFLOW
    hls::stream<fe_pair> s0("s0"), s1("s1"), s2("s2"), s3("s3"), s4("s4"),
                         s5("s5"), s6("s6"), s7("s7"), s8("s8");
    hls::stream<fe_mean> ms("ms");
#pragma HLS STREAM variable=ms depth=32
    fe_window(in_stream, s0, ms, nRamps);
    fe_stage<0>(s0, s1, nRamps);
    fe_stage<1>(s1, s2, nRamps);
    fe_stage<2>(s2, s3, nRamps);
    fe_stage<3>(s3, s4, nRamps);
    fe_stage<4>(s4, s5, nRamps);
    fe_stage<5>(s5, s6, nRamps);
    fe_stage<6>(s6, s7, nRamps);
    fe_stage<7>(s7, s8, nRamps);
    fe_out(s8, ms, out_stream, nRamps);
}
