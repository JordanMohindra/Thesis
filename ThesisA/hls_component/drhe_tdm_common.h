#ifndef DRHE_TDM_COMMON_H
#define DRHE_TDM_COMMON_H

// ---------------------------------------------------------------------------
// TDM-MIMO aware DRHE.
//
// The baseline drhe_compress.cpp predicts ramp m from ramp m-1. That is correct
// for a single-transmitter radar, which is the case Kiem's thesis addresses. It
// is NOT correct for a TDM-MIMO cascade. In the ColoRadar cascade capture the
// 12 TX antennas fire in sequence inside every chirp loop, so the ramp axis is
//
//     ramp = chirpLoop * nTx + txIndex
//
// and ramp m-1 is a DIFFERENT physical transmitter 11 times out of 12. The two
// ramps therefore differ by the array steering phase of the target, which is
// large and target-angle dependent. The DRHE phase model is a double integrator
// that assumes a constant phase increment between successive ramps; a per-ramp
// TX change violates that assumption, and measurement confirms the predictor
// then does worse than no prediction at all.
//
// The fix is to keep one predictor state per transmitter and predict ramp m from
// ramp m - nTx, which is the previous ramp of the SAME transmitter and therefore
// a genuine slow-time (Doppler) neighbour. The algorithm, the coefficients, the
// S4/APPEND format and the Huffman dictionary are all unchanged; only the state
// indexing changes. The cost is nTx copies of the predictor state.
// ---------------------------------------------------------------------------

#include "drhe_common.h"

const int TDM_MAX_NTX = 12;   // ColoRadar cascade: 4 chips x 3 TX
const int TDM_MAX_N   = 128;  // Range bins kept (positive half of a 256-pt FFT)

// Flattened state index: one [TDM_MAX_N] history per transmitter.
inline int tdm_state_index(int tx, int s) { return tx * TDM_MAX_N + s; }

const int TDM_STATE_SIZE = TDM_MAX_NTX * TDM_MAX_N;

// Re-derived Huffman dictionary for DRHE lag nTx (thesis report, dictionary section):
// code lengths from verify_indep/retrain_complete.json "drhe12" (trained on ColoRadar
// frames 0-4, +1 pseudo-count so every S4 keeps a codeword). Canonical codes,
// bit-reversed for the LSB-first bit buffer. Replaces Kiem's Appendix A table here.
const DictEntry_t DRHE_TDM_HUFFMAN_TABLE[16] = {
    {0x0003, 3}, // S4 = 0 : 011 (reversed from 110)
    {0x0001, 2}, // S4 = 1 : 01 (reversed from 10)
    {0x0000, 1}, // S4 = 2 : 0 (reversed from 0)
    {0x0007, 4}, // S4 = 3 : 0111 (reversed from 1110)
    {0x000F, 5}, // S4 = 4 : 01111 (reversed from 11110)
    {0x001F, 6}, // S4 = 5 : 011111 (reversed from 111110)
    {0x003F, 7}, // S4 = 6 : 0111111 (reversed from 1111110)
    {0x007F, 8}, // S4 = 7 : 01111111 (reversed from 11111110)
    {0x00FF, 9}, // S4 = 8 : 011111111 (reversed from 111111110)
    {0x01FF, 10}, // S4 = 9 : 0111111111 (reversed from 1111111110)
    {0x03FF, 11}, // S4 = 10: 01111111111 (reversed from 11111111110)
    {0x1FFF, 14}, // S4 = 11: 01111111111111 (reversed from 11111111111110)
    {0x3FFF, 14}, // S4 = 12: 11111111111111 (reversed from 11111111111111)
    {0x07FF, 13}, // S4 = 13: 0011111111111 (reversed from 1111111111100)
    {0x17FF, 13}, // S4 = 14: 1011111111111 (reversed from 1111111111101)
    {0x0FFF, 13}  // S4 = 15: 0111111111111 (reversed from 1111111111110)
};


#endif // DRHE_TDM_COMMON_H
