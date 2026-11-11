#ifndef RADAR_FE_H
#define RADAR_FE_H
#include "radar_fe_types.h"

// Range-FFT front end: raw ADC ramps in, FX16 range bins out.
//   in_stream : per ramp, 256 beats; beat s = sample s of RX0..3, each 32 bits
//               (bits 15:0 I, 31:16 Q, int16)
//   out_stream: per ramp, 128 beats; beat k = range bin k of RX0..3 in the same
//               packing, i.e. exactly the compressors' input. TLAST on the last
//               beat of the frame.
// Per ramp and channel it computes, like the MATLAB chain,
//   code[k] = int16(round( FFT(w .* (x - mean(x)))[k] / 63.75 )),  k = 0..127
void radar_fe(hls::stream<fe_axis_t>& in_stream,
              hls::stream<fe_axis_t>& out_stream,
              int nRamps);

#endif
