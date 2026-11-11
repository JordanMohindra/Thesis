#ifndef RADAR_FE_TYPES_H
#define RADAR_FE_TYPES_H
// Number formats of the range-FFT front end (radar_fe.cpp).
#include <ap_int.h>
#include <ap_fixed.h>
#include <hls_stream.h>
#include <ap_axi_sdata.h>

#define FE_N    256   // ADC samples per ramp = FFT length
#define FE_NB   128   // range bins kept (positive half)
#define FE_NRX  4     // receive channels per 128-bit beat

typedef hls::axis<ap_uint<128>, 0, 0, 0> fe_axis_t;    // same as the compressors' axis_128_t

typedef ap_ufixed<18, 0>                 win_t;  // Hann window, 2^-18 steps
typedef ap_fixed<18, 2>                  tw_t;   // twiddle cos/sin, 2^-16 steps
typedef ap_fixed<32, 9>                  wh_t;   // FFT of the window, 2^-23 steps
// FFT data: |X| <= 256 * 32768 = 2^23, so 25 integer bits + sign; 10 fraction bits
// keep the accumulated rounding far below the output step of 63.75.
typedef ap_fixed<36, 26, AP_RND, AP_WRAP> fx_t;
typedef ap_fixed<26, 18>                 mu_t;   // ramp mean = sum / 256, exact
typedef ap_fixed<16, 16, AP_RND_INF, AP_SAT> code_t;   // MATLAB int16(round(.)): half away from zero, saturate

struct fe_cx    { fx_t re, im; };
struct fe_pair  { fe_cx a[FE_NRX]; fe_cx b[FE_NRX]; };   // two FFT points, all channels
struct fe_mean  { mu_t re[FE_NRX]; mu_t im[FE_NRX]; };

#endif
