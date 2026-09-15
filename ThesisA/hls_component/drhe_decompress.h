#ifndef DRHE_DECOMPRESS_H
#define DRHE_DECOMPRESS_H

#include "drhe_common.h"

void drhe_decompress(
    hls::stream<axis_256_t>& in_stream,
    hls::stream<axis_128_t>& out_stream,
    int nSamples,
    int nRamps,
    int nRX
);

#endif // DRHE_DECOMPRESS_H
