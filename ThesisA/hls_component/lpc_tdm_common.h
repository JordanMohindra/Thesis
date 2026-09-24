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

#endif // LPC_TDM_COMMON_H
