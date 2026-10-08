#ifndef LPC_TDM_COMMON_H
#define LPC_TDM_COMMON_H

// ---------------------------------------------------------------------------
// TDM-MIMO aware LPC.
//
// The baseline lpc_compress.cpp fits x_hat[m] = a1*x[m-1] + a2*x[m-2] along the
// ramp axis. On a TDM-MIMO cascade that axis is interleaved by transmitter
// (ramp = chirpLoop*nTx + txIndex), so lags 1 and 2 reach a DIFFERENT physical
// transmitter and the fitted coefficients describe the TX switching pattern
// rather than target Doppler.
//
// This variant fits x_hat[m] = a1*x[m-nTx] + a2*x[m-2*nTx], i.e. the same
// second-order model evaluated on the true slow-time axis. The Yule-Walker
// solve, the stability test, the coefficient quantisation, the S4/APPEND format
// and the Huffman dictionary are all unchanged, and because there is still one
// coefficient pair per (range bin, channel, I/Q) the side-information overhead
// is identical to the baseline.
//
// Two structural changes follow:
//   * the autocorrelations now need lags nTx and 2*nTx, so they are accumulated
//     in pass 2 from the frame buffer through a 2*nTx-deep shift register of
//     scalars, instead of in pass 1 through per-(channel,bin) history arrays.
//     That deletes six 64-bit accumulator arrays and four short arrays, and
//     leaves the ingest loop as pure buffering.
//   * the residual pass keeps a 2*nTx-deep reconstruction history rather than
//     two scalars.
// ---------------------------------------------------------------------------

#include "lpc_common.h"

const int LPC_TDM_MAX_NTX = 12;              // ColoRadar cascade
const int LPC_TDM_HIST    = 2 * LPC_TDM_MAX_NTX;  // deepest lag needed

// Re-derived Huffman dictionary for LPC lags nTx, 2nTx (thesis report, dictionary section):
// code lengths from verify_indep/retrain_complete.json "lpc1224" (trained on ColoRadar
// frames 0-4, +1 pseudo-count so every S4 keeps a codeword). Canonical codes,
// bit-reversed for the LSB-first bit buffer. Replaces Kiem's Appendix A table here.
const DictEntry_t LPC_TDM_HUFFMAN_TABLE[16] = {
    {0x0003, 3}, // S4 = 0 : 011 (reversed from 110)
    {0x0000, 1}, // S4 = 1 : 0 (reversed from 0)
    {0x0001, 2}, // S4 = 2 : 01 (reversed from 10)
    {0x0007, 4}, // S4 = 3 : 0111 (reversed from 1110)
    {0x000F, 5}, // S4 = 4 : 01111 (reversed from 11110)
    {0x001F, 6}, // S4 = 5 : 011111 (reversed from 111110)
    {0x003F, 7}, // S4 = 6 : 0111111 (reversed from 1111110)
    {0x007F, 8}, // S4 = 7 : 01111111 (reversed from 11111110)
    {0x00FF, 9}, // S4 = 8 : 011111111 (reversed from 111111110)
    {0x01FF, 10}, // S4 = 9 : 0111111111 (reversed from 1111111110)
    {0x07FF, 13}, // S4 = 10: 0011111111111 (reversed from 1111111111100)
    {0x17FF, 13}, // S4 = 11: 1011111111111 (reversed from 1111111111101)
    {0x0FFF, 13}, // S4 = 12: 0111111111111 (reversed from 1111111111110)
    {0x1FFF, 13}, // S4 = 13: 1111111111111 (reversed from 1111111111111)
    {0x03FF, 12}, // S4 = 14: 001111111111 (reversed from 111111111100)
    {0x0BFF, 12}  // S4 = 15: 101111111111 (reversed from 111111111101)
};


#endif // LPC_TDM_COMMON_H
