#ifndef LPC_DECOMPRESS_H
#define LPC_DECOMPRESS_H

#include "lpc_common.h"

void lpc_decompress(
    hls::stream<axis_256_t>& in_stream,
    hls::stream<axis_128_t>& out_stream,
    int nSamples,
    int nRamps,
    int nRX
);

#endif // LPC_DECOMPRESS_H
