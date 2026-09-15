#ifndef DRHE_COMPRESS_H
#define DRHE_COMPRESS_H

#include "drhe_common.h"

void drhe_compress(
    hls::stream<axis_128_t>& in_stream,
    hls::stream<axis_256_t>& out_stream,
    int nSamples,
    int nRamps,
    int nRX
);

#endif // DRHE_COMPRESS_H
