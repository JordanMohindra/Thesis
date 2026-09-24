#include "lpc_tdm_common.h"
#include "lpc_tdm_compress.h"
#include "lpc_tdm_decompress.h"

void lpc_tdm_top(
    hls::stream<axis_128_t>& in_stream,
    hls::stream<axis_256_t>& out_stream,
    int nSamples,
    int nRamps,
    int nRX,
    int nTx
) {
#pragma HLS INTERFACE axis port=in_stream
#pragma HLS INTERFACE axis port=out_stream
#pragma HLS INTERFACE s_axilite port=nSamples bundle=control
#pragma HLS INTERFACE s_axilite port=nRamps bundle=control
#pragma HLS INTERFACE s_axilite port=nRX bundle=control
#pragma HLS INTERFACE s_axilite port=nTx bundle=control
#pragma HLS INTERFACE s_axilite port=return bundle=control

    lpc_tdm_compress(in_stream, out_stream, nSamples, nRamps, nRX, nTx);
}
