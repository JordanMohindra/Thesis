#ifndef DRHE_COMMON_H
#define DRHE_COMMON_H

#include <ap_fixed.h>
#include <ap_int.h>
#include <hls_stream.h>
#include <ap_axi_sdata.h>
#include <hls_math.h>

// Precision Data Types
typedef ap_fixed<16, 16, AP_RND> fft_data;        // 16-bit signed integer format for Range-FFT
typedef ap_ufixed<16, 16, AP_RND> mag_data;       // 16-bit unsigned magnitude
typedef ap_fixed<16, 3, AP_RND> phase_data;       // 16-bit signed phase [-PI, PI] (1 sign, 2 int, 13 frac)
typedef ap_fixed<32, 4, AP_RND> intermediate_phase_data; // 32-bit for intermediate phase prediction

// Architecture Parameters
const int MAX_NRX = 4;     // Maximum RX channels
const int MAX_N = 1024;    // Maximum Range FFT bins per chirp

// IIR Filter Coefficients
const float ALPHA = 0.6f;  // Magnitude prediction coefficient
const float BETA = 0.4f;   // Phase prediction coefficient

// Struct for Huffman Dictionary Entry
struct DictEntry_t {
    ap_uint<14> code;
    ap_uint<4> len;
};

// Fixed Huffman Dictionary — bit-reversed for LSB-first packing
// Original codes (MSB-first) from thesis Table A.1, reversed for our LSB-first bit buffer.
const DictEntry_t HUFFMAN_TABLE[16] = {
    {0x0005, 4},  // S4 = 0  : 0101 (reversed from 1010)
    {0x0001, 3},  // S4 = 1  : 001  (reversed from 100)
    {0x0002, 2},  // S4 = 2  : 10   (reversed from 01)
    {0x0000, 2},  // S4 = 3  : 00   (reversed from 00)
    {0x0003, 2},  // S4 = 4  : 11   (reversed from 11)
    {0x000D, 5},  // S4 = 5  : 01101 (reversed from 10110)
    {0x001D, 6},  // S4 = 6  : 011101 (reversed from 101110)
    {0x003D, 7},  // S4 = 7  : 0111101 (reversed from 1011110)
    {0x007D, 8},  // S4 = 8  : 01111101 (reversed from 10111110)
    {0x00FD, 9},  // S4 = 9  : 011111101 (reversed from 101111110)
    {0x01FD, 10}, // S4 = 10 : 0111111101 (reversed from 1011111110)
    {0x03FD, 11}, // S4 = 11 : 01111111101 (reversed from 10111111110)
    {0x3FFD, 14}, // S4 = 12 : 11111111111101 (reversed from 10111111111111)
    {0x1FFD, 14}, // S4 = 13 : 01111111111101 (reversed from 10111111111110)
    {0x0FFD, 13}, // S4 = 14 : 0111111111101 (reversed from 1011111111110)
    {0x07FD, 12}  // S4 = 15 : 011111111101 (reversed from 101111111110)
};

// Helper: Calculate S4 Region (0 to 15) for a residual value
inline ap_uint<4> get_s4_region(int diff_val) {
    int abs_v = (diff_val < 0) ? -diff_val : diff_val;
    if (diff_val == 0) return 0;
    if (abs_v == 1) return 1;
    if (abs_v <= 3) return 2;
    if (abs_v <= 7) return 3;
    if (abs_v <= 15) return 4;
    if (abs_v <= 31) return 5;
    if (abs_v <= 63) return 6;
    if (abs_v <= 127) return 7;
    if (abs_v <= 255) return 8;
    if (abs_v <= 511) return 9;
    if (abs_v <= 1023) return 10;
    if (abs_v <= 2047) return 11;
    if (abs_v <= 4095) return 12;
    if (abs_v <= 8191) return 13;
    if (abs_v <= 16383) return 14;
    return 15;
}

// Helper: Calculate APPEND bits for residual value
inline ap_uint<15> get_append_bits(int diff_val, ap_uint<4> s4) {
    if (s4 == 0) return 0;
    if (diff_val < 0) {
        int offset = (1 << s4) - 1;
        return (ap_uint<15>)(diff_val + offset);
    } else {
        return (ap_uint<15>)diff_val;
    }
}

// Helper: Decode APPEND bits back to residual value
inline int decode_append_bits(ap_uint<15> append_bits, ap_uint<4> s4) {
    if (s4 == 0) return 0;
    // Check sign bit (msb of s4 bits)
    bool is_negative = ((append_bits >> (s4 - 1)) & 1) == 0;
    if (is_negative) {
        int offset = (1 << s4) - 1;
        return (int)append_bits - offset;
    } else {
        return (int)append_bits;
    }
}

// AXI-Stream Data Structures
typedef hls::axis<ap_uint<128>, 0, 0, 0> axis_128_t;
typedef hls::axis<ap_uint<256>, 0, 0, 0> axis_256_t;

#endif // DRHE_COMMON_H
