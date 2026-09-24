#ifndef LPC_TDM_DECOMPRESS_H
#define LPC_TDM_DECOMPRESS_H

#include "lpc_tdm_common.h"

void lpc_tdm_decompress(
    hls::stream<axis_256_t>& in_stream,
    hls::stream<axis_128_t>& out_stream,
    int nSamples,
    int nRamps,
    int nRX,
    int nTx
);

#endif // LPC_TDM_DECOMPRESS_H
