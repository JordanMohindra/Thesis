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

#endif // DRHE_TDM_COMMON_H
