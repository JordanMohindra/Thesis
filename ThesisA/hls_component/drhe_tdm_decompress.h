#ifndef DRHE_TDM_DECOMPRESS_H
#define DRHE_TDM_DECOMPRESS_H

#include "drhe_tdm_common.h"

void drhe_tdm_decompress(
    hls::stream<axis_256_t>& in_stream,
    hls::stream<axis_128_t>& out_stream,
    int nSamples,
    int nRamps,
    int nRX,
    int nTx
);

#endif // DRHE_TDM_DECOMPRESS_H
