#ifndef LPC_TDM_COMPRESS_H
#define LPC_TDM_COMPRESS_H

#include "lpc_tdm_common.h"

void lpc_tdm_compress(
    hls::stream<axis_128_t>& in_stream,
    hls::stream<axis_256_t>& out_stream,
    int nSamples,
    int nRamps,
    int nRX,
    int nTx
);

#endif // LPC_TDM_COMPRESS_H
