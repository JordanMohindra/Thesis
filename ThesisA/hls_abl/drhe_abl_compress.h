#ifndef DRHE_ABL_COMPRESS_H
#define DRHE_ABL_COMPRESS_H
#include "drhe_abl_common.h"
void drhe_abl_compress(hls::stream<axis_128_t>& in_stream, hls::stream<axis_256_t>& out_stream,
                       int nSamples, int nRamps, int nRX);
void drhe_abl_decompress(hls::stream<axis_256_t>& in_stream, hls::stream<axis_128_t>& out_stream,
                         int nSamples, int nRamps, int nRX);
#endif
