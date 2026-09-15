#include <iostream>
#include <fstream>
#include <vector>
#include <cmath>
#include <cstdlib>
#include <cstdint>

#include "lpc_compress.h"
#include "lpc_decompress.h"

int main() {
    std::cout << "==========================================================" << std::endl;
    std::cout << " LPC + Huffman Compression Vitis HLS Testbench             " << std::endl;
    std::cout << " Multi-Frame ColoRadar Cascade Dataset                     " << std::endl;
    std::cout << " Target FPGA: AMD Kintex UltraScale+ (xcku5p-ffvb676-2-e) " << std::endl;
    std::cout << "==========================================================" << std::endl;

    // ------------------------------------------------------------------
    // 1. Load binary header exported by MATLAB export_frames_for_vitis.m
    // ------------------------------------------------------------------
    std::string bin_path = "coloradar_multiframe.bin";
    std::ifstream bin_file(bin_path, std::ios::binary);

    if (!bin_file.is_open()) {
        std::cerr << "[ERROR] Could not open " << bin_path << std::endl;
        std::cerr << "        Run export_frames_for_vitis.m in MATLAB first." << std::endl;
        return 1;
    }

    // Read header: [nFrames, nSamples, nRamps, nRX] as uint32
    uint32_t nFrames = 0, nSamples = 0, nRamps = 0, nRX = 0;
    bin_file.read(reinterpret_cast<char*>(&nFrames),  sizeof(uint32_t));
    bin_file.read(reinterpret_cast<char*>(&nSamples), sizeof(uint32_t));
    bin_file.read(reinterpret_cast<char*>(&nRamps),   sizeof(uint32_t));
    bin_file.read(reinterpret_cast<char*>(&nRX),      sizeof(uint32_t));

    std::cout << "[INFO] Loaded header: " << nFrames << " frames x "
              << nRamps << " ramps x " << nSamples << " samples x "
              << nRX << " RX channels" << std::endl;

    if (nRX > MAX_NRX) {
        std::cerr << "[ERROR] nRX=" << nRX << " exceeds MAX_NRX=" << MAX_NRX << std::endl;
        return 1;
    }
    if (nSamples > MAX_N) {
        std::cerr << "[ERROR] nSamples=" << nSamples << " exceeds MAX_N=" << MAX_N << std::endl;
        return 1;
    }

    // ------------------------------------------------------------------
    // 2. Process each frame: Compress -> Decompress -> Verify
    // ------------------------------------------------------------------
    struct Sample {
        int re[MAX_NRX];
        int im[MAX_NRX];
    };

    // Accumulators for global metrics
    double global_total_input_bits = 0;
    double global_total_output_bits = 0;
    int    global_max_diff = 0;
    double global_total_sq_err = 0.0;
    double global_total_signal_pwr = 0.0;
    long   global_total_samples = 0;
    int    frames_processed = 0;
    double sum_per_frame_cr = 0.0;

    for (uint32_t frame = 0; frame < nFrames; frame++) {
        // Allocate per-frame storage
        std::vector<std::vector<Sample>> orig_frame(nRamps, std::vector<Sample>(nSamples));

        // Create fresh streams for each frame
        hls::stream<axis_128_t> compress_in("compress_in");
        hls::stream<axis_256_t> compress_out("compress_out");
        hls::stream<axis_128_t> decompress_out("decompress_out");

        // ---- 2a. Load frame data & push to compressor input stream ----
        for (uint32_t r = 0; r < nRamps; r++) {
            for (uint32_t s = 0; s < nSamples; s++) {
                axis_128_t in_pkt;
                ap_uint<128> raw_128 = 0;

                for (uint32_t ch = 0; ch < nRX; ch++) {
                    short re_val = 0, im_val = 0;
                    bin_file.read(reinterpret_cast<char*>(&re_val), sizeof(short));
                    bin_file.read(reinterpret_cast<char*>(&im_val), sizeof(short));

                    orig_frame[r][s].re[ch] = (int)re_val;
                    orig_frame[r][s].im[ch] = (int)im_val;

                    ap_uint<32> ch_data = 0;
                    ch_data.range(15, 0) = (ap_uint<16>)(ap_int<16>)re_val;
                    ch_data.range(31, 16) = (ap_uint<16>)(ap_int<16>)im_val;

                    raw_128.range((ch + 1) * 32 - 1, ch * 32) = ch_data;
                }

                in_pkt.data = raw_128;
                in_pkt.last = (r == nRamps - 1 && s == nSamples - 1) ? 1 : 0;
                in_pkt.keep = -1;
                compress_in.write(in_pkt);
            }
        }

        // ---- 2b. Run Compression ----
        lpc_compress(compress_in, compress_out, nSamples, nRamps, nRX);

        int num_compressed_packets = compress_out.size();
        long total_input_bits = (long)nRamps * nSamples * nRX * 32;
        long total_output_bits = (long)num_compressed_packets * 256;
        double frame_cr = (double)total_input_bits / (double)total_output_bits;

        // ---- 2c. Run Decompression ----
        lpc_decompress(compress_out, decompress_out, nSamples, nRamps, nRX);

        // ---- 2d. Verify Reconstruction ----
        int frame_max_diff = 0;
        double frame_sq_err = 0.0;
        double frame_signal_pwr = 0.0;
        int frame_total_samples = nRamps * nSamples * nRX * 2;

        for (uint32_t r = 0; r < nRamps; r++) {
            for (uint32_t s = 0; s < nSamples; s++) {
                if (decompress_out.empty()) {
                    std::cerr << "[ERROR] Frame " << frame << ": premature end at r=" << r << " s=" << s << std::endl;
                    return 1;
                }

                axis_128_t out_pkt = decompress_out.read();
                ap_uint<128> raw_out = out_pkt.data;

                for (uint32_t ch = 0; ch < nRX; ch++) {
                    ap_uint<32> ch_data = raw_out.range((ch + 1) * 32 - 1, ch * 32);
                    ap_int<16> rec_re = ch_data.range(15, 0);
                    ap_int<16> rec_im = ch_data.range(31, 16);

                    int orig_re = orig_frame[r][s].re[ch];
                    int orig_im = orig_frame[r][s].im[ch];

                    int diff_re = std::abs((int)rec_re - orig_re);
                    int diff_im = std::abs((int)rec_im - orig_im);

                    if (diff_re > frame_max_diff) frame_max_diff = diff_re;
                    if (diff_im > frame_max_diff) frame_max_diff = diff_im;

                    frame_sq_err += (double)(diff_re * diff_re + diff_im * diff_im);
                    frame_signal_pwr += (double)orig_re * orig_re + (double)orig_im * orig_im;
                }
            }
        }

        // ---- 2e. Print per-frame summary ----
        std::cout << "  Frame " << frame << ": CR=" << frame_cr << "x"
                  << "  MaxDiff=" << frame_max_diff
                  << "  Bits=" << total_input_bits << "->" << total_output_bits;
        if (frame_max_diff == 0) {
            std::cout << "  [LOSSLESS]" << std::endl;
        } else {
            double frame_snr = 10.0 * std::log10(frame_signal_pwr / (frame_sq_err + 1e-12));
            std::cout << "  SNR=" << frame_snr << "dB" << std::endl;
        }

        // Accumulate global metrics
        global_total_input_bits += total_input_bits;
        global_total_output_bits += total_output_bits;
        if (frame_max_diff > global_max_diff) global_max_diff = frame_max_diff;
        global_total_sq_err += frame_sq_err;
        global_total_signal_pwr += frame_signal_pwr;
        global_total_samples += frame_total_samples;
        sum_per_frame_cr += frame_cr;
        frames_processed++;
    }

    bin_file.close();

    // ------------------------------------------------------------------
    // 3. Print Global Results
    // ------------------------------------------------------------------
    double avg_cr = sum_per_frame_cr / frames_processed;
    double overall_cr = global_total_input_bits / global_total_output_bits;
    double global_mse = global_total_sq_err / global_total_samples;

    std::cout << std::endl;
    std::cout << "==========================================================" << std::endl;
    std::cout << " GLOBAL VERIFICATION RESULTS (" << frames_processed << " frames)" << std::endl;
    std::cout << "==========================================================" << std::endl;
    std::cout << " Max LSB Difference    : " << global_max_diff << std::endl;
    std::cout << " Mean Squared Error     : " << global_mse << std::endl;
    if (global_total_sq_err == 0) {
        std::cout << " Signal-to-Noise Ratio : INFINITE (Lossless)" << std::endl;
    } else {
        double global_snr = 10.0 * std::log10(global_total_signal_pwr / (global_total_sq_err + 1e-12));
        std::cout << " Signal-to-Noise Ratio : " << global_snr << " dB" << std::endl;
    }
    std::cout << " Average CR (per-frame): " << avg_cr << "x" << std::endl;
    std::cout << " Overall CR (aggregate): " << overall_cr << "x" << std::endl;
    std::cout << " Total Input           : " << (long long)global_total_input_bits / 8 / 1024 << " KB" << std::endl;
    std::cout << " Total Compressed      : " << (long long)global_total_output_bits / 8 / 1024 << " KB" << std::endl;
    std::cout << "==========================================================" << std::endl;

    if (global_max_diff == 0) {
        std::cout << "[SUCCESS] All " << frames_processed << " frames: LOSSLESS reconstruction!" << std::endl;
        return 0;
    } else if (global_max_diff <= 1) {
        std::cout << "[SUCCESS] All " << frames_processed << " frames: near-lossless (max +-1 LSB)." << std::endl;
        return 0;
    } else {
        std::cout << "[FAILURE] Reconstruction error too large (max_diff=" << global_max_diff << ")." << std::endl;
        return 1;
    }
}
