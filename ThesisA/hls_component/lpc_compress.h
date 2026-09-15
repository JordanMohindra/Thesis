#ifndef LPC_COMPRESS_H
#define LPC_COMPRESS_H

#include "lpc_common.h"

void lpc_compress(
    hls::stream<axis_128_t>& in_stream,
    hls::stream<axis_256_t>& out_stream,
    int nSamples,
    int nRamps,
    int nRX
);

#endif // LPC_COMPRESS_H
