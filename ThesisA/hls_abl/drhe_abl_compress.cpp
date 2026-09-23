#include "drhe_abl_compress.h"
#include <cmath>

void drhe_abl_compress(
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

    static st_mag_t s_mag_pred[MAX_NRX][MAX_N];
    static st_mag_t s_prev_mag[MAX_NRX][MAX_N];
    static st_phs_t s_phase_pred[MAX_NRX][MAX_N];
    static st_phs_t s_prev_phase[MAX_NRX][MAX_N];
    static st_phs_t s_prev_prev_phase[MAX_NRX][MAX_N];

#pragma HLS ARRAY_PARTITION variable=s_mag_pred complete dim=1
#pragma HLS ARRAY_PARTITION variable=s_prev_mag complete dim=1
#pragma HLS ARRAY_PARTITION variable=s_phase_pred complete dim=1
#pragma HLS ARRAY_PARTITION variable=s_prev_phase complete dim=1
#pragma HLS ARRAY_PARTITION variable=s_prev_prev_phase complete dim=1

    ap_uint<512> bit_buffer = 0;
#if ABL_PACK == 0
    int bit_count = 0;
#elif ABL_PACK == 1
    ap_uint<10> bit_count = 0;
#elif ABL_PACK == 3
    int bit_count = 0;   // naive reading of Kiem Sec. 4.3.4: per-channel insert, int counter
#else
    ap_uint<9> bit_count = 0;
#endif

    RAMP_LOOP: for (int r = 0; r < nRamps; r++) {
        SAMPLE_LOOP: for (int s = 0; s < nSamples; s++) {
#pragma HLS PIPELINE II=1
#ifdef ABL_DEPTH23
            // stretch one iteration so the loop depth equals Kiem's reported 23 cycles (his Sec. 4.4.1
            // split the arithmetic into extra registered steps to close timing)
#pragma HLS LATENCY min=22
#endif

            axis_128_t in_pkt = in_stream.read();
            ap_uint<128> raw_in = in_pkt.data;
#if ABL_PACK >= 2
            ap_uint<58> ch_word[MAX_NRX];
            ap_uint<6>  ch_len[MAX_NRX];
#pragma HLS ARRAY_PARTITION variable=ch_word complete
#pragma HLS ARRAY_PARTITION variable=ch_len complete
#endif

            CHANNEL_LOOP: for (int ch = 0; ch < MAX_NRX; ch++) {
#pragma HLS UNROLL
#if ABL_PACK >= 2
                ch_word[ch] = 0;
                ch_len[ch]  = 0;
#endif
                if (ch < nRX) {
#if ABL_RESET == 0
                    if (r == 0) {
                        s_mag_pred[ch][s] = 0;
                        s_prev_mag[ch][s] = 0;
                        s_phase_pred[ch][s] = 0;
                        s_prev_phase[ch][s] = 0;
                        s_prev_prev_phase[ch][s] = 0;
                    }
                    st_mag_t pmp = s_mag_pred[ch][s];
                    st_mag_t pm  = s_prev_mag[ch][s];
                    st_phs_t ppp = s_phase_pred[ch][s];
                    st_phs_t pp  = s_prev_phase[ch][s];
                    st_phs_t pp2 = s_prev_prev_phase[ch][s];
#else
                    bool first = (r == 0);
                    st_mag_t pmp = first ? (st_mag_t)0 : s_mag_pred[ch][s];
                    st_mag_t pm  = first ? (st_mag_t)0 : s_prev_mag[ch][s];
                    st_phs_t ppp = first ? (st_phs_t)0 : s_phase_pred[ch][s];
                    st_phs_t pp  = first ? (st_phs_t)0 : s_prev_phase[ch][s];
                    st_phs_t pp2 = first ? (st_phs_t)0 : s_prev_prev_phase[ch][s];
#endif
                    ap_uint<32> ch_data = raw_in.range((ch + 1) * 32 - 1, ch * 32);
                    ap_int<16> re_raw = ch_data.range(15, 0);
                    ap_int<16> im_raw = ch_data.range(31, 16);
                    int re = (int)re_raw;
                    int im = (int)im_raw;

                    int pred_re, pred_im;
                    st_mag_t mag_pred;
                    st_phs_t phase_pred;
                    abl_predict(pmp, pm, ppp, pp, pp2, pred_re, pred_im, mag_pred, phase_pred);

                    int diff_re = abl_wrap16(re - pred_re);
                    int diff_im = abl_wrap16(im - pred_im);
                    if (diff_re == -32768) diff_re = -32767;
                    if (diff_im == -32768) diff_im = -32767;

#if ABL_LOOP == 0
                    int src_re = abl_wrap16(diff_re + pred_re);
                    int src_im = abl_wrap16(diff_im + pred_im);
#else
                    int src_re = re;
                    int src_im = im;
#endif
                    st_mag_t curr_mag;
                    st_phs_t curr_phase;
                    abl_polar(src_re, src_im, curr_mag, curr_phase);

                    s_prev_prev_phase[ch][s] = pp;
                    s_prev_phase[ch][s]      = curr_phase;
                    s_phase_pred[ch][s]      = phase_pred;
                    s_prev_mag[ch][s]        = curr_mag;
                    s_mag_pred[ch][s]        = mag_pred;

                    ap_uint<4> s4_re = get_s4_region(diff_re);
                    ap_uint<15> append_re = get_append_bits(diff_re, s4_re);
                    DictEntry_t huff_re = HUFFMAN_TABLE[s4_re];
                    ap_uint<4> s4_im = get_s4_region(diff_im);
                    ap_uint<15> append_im = get_append_bits(diff_im, s4_im);
                    DictEntry_t huff_im = HUFFMAN_TABLE[s4_im];

#if ABL_PACK >= 2
                    ap_uint<29> code_re = ((ap_uint<29>)append_re << huff_re.len) | (ap_uint<29>)huff_re.code;
                    ap_uint<5>  len_re  = huff_re.len + s4_re;
                    ap_uint<29> code_im = ((ap_uint<29>)append_im << huff_im.len) | (ap_uint<29>)huff_im.code;
                    ap_uint<5>  len_im  = huff_im.len + s4_im;
                    ch_word[ch] = (ap_uint<58>)code_re | ((ap_uint<58>)code_im << len_re);
                    ch_len[ch]  = (ap_uint<6>)len_re + len_im;
#if ABL_PACK == 3
                    // each channel's 58-bit word goes straight into the output buffer
                    bit_buffer |= ((ap_uint<512>)ch_word[ch] << bit_count);
                    bit_count += ch_len[ch];
#endif
#elif ABL_PACK == 1
                    ap_uint<32> code_re = ((ap_uint<32>)append_re << huff_re.len) | (ap_uint<32>)huff_re.code;
                    ap_uint<5>  len_re  = huff_re.len + s4_re;
                    ap_uint<32> code_im = ((ap_uint<32>)append_im << huff_im.len) | (ap_uint<32>)huff_im.code;
                    ap_uint<5>  len_im  = huff_im.len + s4_im;
                    bit_buffer |= ((ap_uint<512>)code_re << bit_count);
                    bit_count += len_re;
                    bit_buffer |= ((ap_uint<512>)code_im << bit_count);
                    bit_count += len_im;
#else
                    ap_uint<32> code_re = ((ap_uint<32>)append_re << huff_re.len) | (ap_uint<32>)huff_re.code;
                    int len_re = huff_re.len + s4_re;
                    ap_uint<32> code_im = ((ap_uint<32>)append_im << huff_im.len) | (ap_uint<32>)huff_im.code;
                    int len_im = huff_im.len + s4_im;
                    bit_buffer |= ((ap_uint<512>)code_re << bit_count);
                    bit_count += len_re;
                    bit_buffer |= ((ap_uint<512>)code_im << bit_count);
                    bit_count += len_im;
#endif
                }
            }

#if ABL_PACK == 2
            // Concatenate the four channel words (Kiem: "combine the compressed data
            // from each RX channel into a 256-bit wide output buffer").
            ap_uint<232> word = ch_word[0];
            ap_uint<8> off = ch_len[0];
            word |= (ap_uint<232>)ch_word[1] << off;  off += ch_len[1];
            word |= (ap_uint<232>)ch_word[2] << off;  off += ch_len[2];
            word |= (ap_uint<232>)ch_word[3] << off;  off += ch_len[3];
            bit_buffer |= ((ap_uint<512>)word << bit_count);
            bit_count += off;
#endif
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
