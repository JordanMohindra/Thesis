#include "drhe_common.h"
#include "drhe_compress.h"
#include "drhe_decompress.h"

// Top-level entry point wrapper for Vitis HLS
void drhe_top(
    hls::stream<axis_128_t>& in_stream,
    hls::stream<axis_256_t>& out_stream,
    int nSamples,
    int nRamps,
    int nRX
) {
#pragma HLS INTERFACE axis port=in_stream
#pragma HLS INTERFACE axis port=out_stream
#pragma HLS INTERFACE s_axilite port=nSamples bundle=control
#pragma HLS INTERFACE s_axilite port=nRamps bundle=control
#pragma HLS INTERFACE s_axilite port=nRX bundle=control
#pragma HLS INTERFACE s_axilite port=return bundle=control

    drhe_compress(in_stream, out_stream, nSamples, nRamps, nRX);
}
