# kiem_replication

This folder rebuilds, from his text alone, the MATLAB simulation workflow of Kiem's thesis, *Design and Implementation of Data Compression Methods for SoC-based Radar Systems* (his Fig. 3.1 and Tables 3.2 and 3.5). It uses his one-transmitter radar and runs both DRHE and LPC on it.

The folder is self-contained. It uses base MATLAB only, needs no toolboxes, and does not call anything in `Matlab_Sim`. The one exception is `kr_crosscheck_matlabsim.m`, a verification script that nothing else depends on.

`FINDINGS.md` covers the conclusions: why Kiem ranks LPC below DRHE, why the early Matlab_Sim runs disagreed with him, and a line-by-line audit of our DRHE against his §3.5.3.

## Running

From this folder:

| Script | What it produces | Time |
|---|---|---|
| `run_kiem_replication` | The main result. Replicated Table 3.5 at two noise levels next to Kiem's; LPC-Huffman by order; figures. Writes `results/run_kiem_replication_log.txt`, `kiem_replication_results.mat`, `fig_rangefft.png`, `fig_rdmap.png` and `fig_s4hist.png`. | ≈ 40 s |
| `kr_noise_sweep` | CR of every method against the noise floor, from −140 to −60 dBFS. Writes `noise_sweep.csv` and `fig_noise_sweep.png`. | ≈ 25 s |
| `kr_tdm_experiment` | 1 TX against 12-TX TDM, lag 1 and lag 12, on Kiem's scene and on a dense scene. Writes `tdm_experiment.txt`. | ≈ 13 s |
| `kr_early_result_check` | The two FX16 scalings at three noise floors; reproduces the early Matlab_Sim CR of about 1.1. Writes `early_result_check.txt`. | ≈ 10 s |
| `kr_dictionary_fingerprint` | The residual level for which Kiem's fixed Huffman dictionary is optimal. Writes `dictionary_fingerprint.txt`. | < 1 s |
| `kr_lpc_raw_method_check` | LPC-Huffman coefficients by the autocorrelation method against the covariance method. Writes `lpc_raw_method_check.txt`. | ≈ 5 s |
| `kr_crosscheck_matlabsim` | Checks that `Matlab_Sim/compress_drhe.m` and this folder's DRHE give identical residuals and bits. Writes `crosscheck_matlabsim.txt`. | ≈ 10 s |

The main script and the TDM experiment log with `diary`. Run from the MATLAB command window, the log fills as normal. Run through `evalc`, for example from an automation tool, `diary` captures nothing; capture the output with `T = evalc('run_kiem_replication')` and write `T` to the log file instead. That is how the logs in `results/` were made.

## Files, and where each comes from in Kiem

| File | Role | Kiem |
|---|---|---|
| `kr_config.m` | Every parameter, with its source or `ASSUMPTION` | Tables 3.2, 3.3, 4.4; App. A |
| `kr_generate_adc.m` | FMCW beat signals, AWGN, 14-bit ADC; optional TDM interleaving | §3.2.2 |
| `kr_calibrate_noise.m` | ADC noise σ that gives a chosen noise floor after NCI | Table 3.2 ("noise level after NCI") |
| `kr_hanning.m`, `kr_preprocess_fft.m` | Shift to 32-bit full scale, Hanning, FFT/N, first half | §3.2.1, §4.3.3 |
| `kr_fp16.m`, `kr_fx16.m` | FP16 reference and FX16 quantisation (`hw` / `peak`) | §3.4.1 |
| `kr_second_stage.m`, `kr_detect.m` | Doppler FFT, NCI, noise-based threshold + local maxima | §3.2.1 |
| `kr_metrics.m`, `kr_fullscale_ref.m` | CR, FN %, FP %, NF est., SNR, against FP16 | §3.4.2 |
| `kr_drhe_predict_step.m`, `kr_drhe_update.m`, `kr_drhe_encode.m`, `kr_drhe_decode.m` | DRHE model prediction and inverse (Eqs. 3.4–3.7) | §3.5.3, §3.5.4 |
| `kr_s4.m`, `kr_wrap16.m`, `kr_bits_s4.m` | S4 regions, APPEND, fixed or ideal Huffman | Table 3.7, §3.5.2, App. A |
| `kr_bits_r4s4.m` | Original R4S4 + RLE coding (DRHE as in Table 3.5) | §2.7.3, §3.5.1 |
| `kr_huffman_lengths.m` | Optimal Huffman code lengths | §2.7.3, §2.7.4 |
| `kr_lpc_raw.m` | LPC-Huffman of [25]: fast-time prediction of raw ADC | §2.7.4 |
| `kr_lpc_fft.m` | This thesis's LPC: slow-time prediction on FX16 (for comparison) | not in Kiem |
| `kr_lossy.m` | Approximations of CMPRA/B and EGE10/8/6/4 | §2.7.1, §2.7.2, Table 3.4 |
| `kr_run_scene.m` | One pass of the whole workflow | Fig. 3.1 |
| `kr_find_nf_for_cr.m` | Noise floor at which DRHE gives a target CR | — |
| `kr_kiem_table.m` | Kiem's published Tables 3.5 and 3.6, for side-by-side printing | Tables 3.5, 3.6 |
| `kr_figures.m` | Figures in the style of his Figs. 3.5, 3.7 and 3.13 | — |

## Assumptions (where Kiem gives no value)

All of these are in `kr_config.m` (or in the named file) and can be changed there.

- **Target angles.** Kiem gives none. The code uses −30°, −10°, 0°, 15° and 40° with a λ/2 ULA, so that the four RX channels differ.
- **Target amplitudes.** His five amplitudes, 0.8, 0.3, 0.4, 0.5 and 0.7 of full scale, sum to 2.7 and would clip a 14-bit ADC. They are scaled together so that the worst-case sum just fits. The `none` option uses them as given.
- **Random seed.** Start phases and noise use seed 1.
- **FX16 scaling.** `hw` keeps the top 16 bits of the 32-bit FFT word, as his FFT IP core does, and is the default. `peak` is the Matlab_Sim scaling, 4× larger.
- **dBFS reference.** Kiem does not define one, so both are reported.
  - `sinusoid`: 0 dBFS is a full-scale sinusoid through the whole chain.
  - `unit`: 0 dBFS is the 32-bit full-scale value. It reads 12.0 dB lower.
- **Detector.** Noise estimate = mean (dB) of the lowest 75 % of cells; threshold = estimate + 15 dB; 8-neighbour local maxima. Cells coded to exactly zero by the lossy schemes are floored at −200 dBFS and left out of the noise estimate and the NF.
- **NF and SNR.** The NF is the mean dB outside 5×5 patches around the reference detections. SNR = RMS peak dB − NF, as in his §3.4.2.
- **LPC-Huffman of [25].** Order p swept 1–10; one coefficient set per chirp and RX, sent as 32-bit floats; dictionary side information 21 bits per used symbol (the CR is also given without it).
- **R4S4 coding.** JPEG conventions: ZRL (15,0) for 16 zeros, EOB (0,0), runs along the range bins, ideal Huffman built from the data, dictionary not counted (as in Kiem's "Ideal" row, Table 2.1). The S4-only ideal Huffman does count its 64 bits of code lengths.
- **Lossy schemes.** These are approximations; the real parameters are proprietary.
  - CMPRA/B: block floating point with one 4-bit exponent per 256-bit word and 7- or 3-bit mantissas.
  - EGE-k: 8 complex bins per block with an 8-bit header, an order chosen from the median, and LSBs dropped to meet CR 16/k.
  - Their FN/FP describe this scene, whose SNR is 60–74 dB, not Kiem's real data at 22 dB.

## Results in one table

This table is from `results/run_kiem_replication_log.txt`, for Kiem's Table 3.2 scene with 1 TX. Every lossless round trip was verified.

| | Kiem's −75 dBFS | NF where DRHE = 3.25 (−87.9 dBFS) | Kiem, Tables 3.5 and 3.6 (real data) |
|---|---|---|---|
| FX16 noise std (LSB) | 20.35 | 4.63 | — |
| DRHE, R4S4 + RLE | 2.28 | **3.25** | 3.25 |
| DRHE, S4 only, ideal Huffman | 2.28 | **3.24** | 3.24 |
| DRHE, S4, fixed dictionary (HW) | 1.85 | 3.23 | (3.17 on HW, different data) |
| LPC-Huffman, raw ADC [25], p = 10 | 1.32 | 1.54 | not run ([25] reports 2.056 on its own data) |
| LPC, slow time (this thesis), fixed dictionary | 2.06 | 3.38 | — |
| No prediction, fixed dictionary | 2.03 | 3.26 | — |

See `FINDINGS.md` for what these numbers mean.
