# Kiem, LPC and DRHE: what the replication shows

Jordan Mohindra, 24 September 2026. All numbers come from the scripts in this folder, and each figure names its script and output file. Section references in square brackets are to Kiem's thesis, *Design and Implementation of Data Compression Methods for SoC-based Radar Systems*.

This note answers four questions:

1. Why does Kiem say LPC is like DRHE but worse, when our results put the two level?
2. Why did the early Matlab_Sim runs give such different numbers from his?
3. Can his MATLAB workflow be rebuilt, one transmitter and all, for both LPC and DRHE?
4. Is our DRHE the algorithm of his §3.5.3, and where it is not, why?

The short answers:

1. Kiem's "LPC" and ours are different algorithms that happen to share a name.
2. The early runs used a noise level and an FX16 scaling that together put about 30 times more noise LSBs into the compressor than his result implies.
3. Yes. The rebuild runs end to end, and it confirms both points above.
4. Our MATLAB DRHE is his §3.5.3 exactly, bit for bit. The HLS DRHE differs in five places: one defect fix, two implementation choices, one clarification and one extension. On Kiem's one-transmitter radar, none of them changes the compressed size by more than 0.07 %.

---

## 1. Kiem's LPC is not our LPC

### What Kiem says, and what he actually compared

In §2.7.4 Kiem describes the method of his reference [25] (Meucci and Mancuso). It is linear prediction of **int16 samples along fast time**: each sample is predicted from the previous *p* samples of the same chirp. The coefficients come from least squares, and the residuals are coded with a Huffman code built from the data. [25] reports CR 2.056. Kiem himself is not sure of the domain: "the input data is said to be int16 data. Therefore, we *assume* that this work is performed on raw ADC data."

In §3.4.1 he then leaves the method out of his design space: "LPC-Huffman compression is not taken because it has the same approach as DRHE, but instead of compressing range FFT data, it operates on raw ADC data; the results for DRHE are more promising."

"More promising" is not a measurement. Kiem never ran LPC. He compared two published figures:

- [25]'s 2.056, on [25]'s data;
- the original DRHE paper's 9.7 to 9.8 (his Table 2.1), on that paper's data.

His Table 3.4 describes DRHE itself as "LPC on range FFT data". In his own words, then, the two differ in the domain they predict in, not in approach.

### What our LPC is

The LPC in this thesis is a different algorithm:

- It predicts **along slow time**, from ramp *m−1* and *m−2* of the **same range bin**.
- It works on the **FX16 range-FFT output**, which is exactly what DRHE sees.
- It fits two Yule–Walker coefficients per (bin, RX, re/im).
- It codes the residuals with **the same fixed S4 dictionary as DRHE**.

So it differs from DRHE only in the predictor: DRHE uses a fixed polar IIR, ours fitted Cartesian coefficients. That is the controlled comparison Kiem never made. It is also why our results show the two close together. The table below brings both comparisons together.

| Comparison | DRHE | LPC | Source |
|---|---|---|---|
| Kiem's scene, −75 dBFS, [25]-style raw-ADC LPC, best order p=10 | 1.85 (fixed dict) / 2.28 (R4S4) | **1.32** | `results/run_kiem_replication_log.txt` |
| Kiem's scene, −87.9 dBFS, [25]-style raw-ADC LPC | 3.23 / 3.25 | **1.54** | same |
| Kiem's scene, −75 dBFS, our slow-time LPC | 1.85 | **2.06** | same |
| Kiem's scene, −87.9 dBFS, our slow-time LPC | 3.23 | **3.38** | same |
| ColoRadar, 12-TX TDM, lag 1 (HLS C-sim, 50 frames) | 3.310 | 3.385 | `claude/correctness_audit_and_tdm_fix.md` |
| ColoRadar, lag n<sub>Tx</sub> (corrected) | **3.751** | 3.697 | same |

**Kiem's ranking holds for the LPC he meant.** On his own simulated scene, [25]-style raw-ADC LPC loses to DRHE by a wide margin at every noise level (`results/noise_sweep.csv`, Figure `fig_noise_sweep.png`). **It does not hold for the LPC we built.** Given the same data and the same entropy coder, slow-time LPC is level with DRHE: it is slightly ahead on Kiem's white-noise scene at every noise floor of −95 dBFS or noisier, and slightly behind on corrected ColoRadar. Which one wins depends on the data, and the margin is a few per cent either way.

### Why raw-ADC LPC loses: it codes information that FX16 has already thrown away

This is the main reason. It follows from Kiem's own processing chain [3.2.1]:

1. Shift the 14-bit ADC samples left by 18 bits.
2. Apply a Hanning window.
3. Take the FFT and divide by N.
4. Keep the top 16 bits (FX16).

White ADC noise of standard deviation σ codes ends up with standard deviation

σ<sub>FX16</sub> = σ · 2<sup>18</sup>/2<sup>16</sup> · √(Σw²/2)/N = σ · 4 · √(0.375/2048) = **0.0541 σ**.

The simulation measures exactly this ratio: 376 → 20.35 LSB and 85.4 → 4.63 LSB. The FFT scaling and the 16-bit truncation therefore discard about log₂(1/0.054) ≈ **4.2 bits of noise per value** before DRHE ever sees the data. Raw-ADC LPC is lossless on the ADC codes, so it has to keep those bits.

At −87.9 dBFS the ADC noise is 85 codes. Even a perfect predictor leaves a residual whose entropy is about log₂(85·√(2πe)) ≈ 8.5 bits, so CR can be at most 16/8.5 ≈ 1.9. The measured value is 1.54. The prediction filter amplifies white noise too: the residual std is 201 codes with least-squares coefficients.

The comparison is between a lossless coder of the ADC data (raw LPC) and a lossless coder of already-truncated data (DRHE). The truncation is the lossy step, and Kiem's Table 3.5 shows its cost in the FX16 row (FN 0.59 %, FP 1.18 %). DRHE inherits that cost; raw-ADC LPC does not.

A second reason is that fast-time prediction must model the whole beat signal. Five real targets need up to 10 poles. The CR rises from p = 1 to p = 10 (1.17 → 1.32 at −75 dBFS; see the log). One coefficient set per chirp also costs 320 bits per chirp.

The coefficient method is not the problem. The autocorrelation (Levinson–Durbin) method is biased for pure sinusoids, and the covariance (true least-squares) method removes that bias. It helps only when there is almost no noise:

- at −140 dBFS, p = 10, CR rises from 1.83 to 6.51;
- at the noise levels that matter it changes nothing: 1.56 → 1.59 at −87.9 dBFS and 1.34 → 1.34 at −75 dBFS.

Source: `kr_lpc_raw_method_check.m`, `results/lpc_raw_method_check.txt`.

---

## 2. Why the early Matlab_Sim results differ from Kiem's

The early runs matched Kiem's NF (−70.7 to −71.0 dBFS) and SNR, but DRHE gave CR 1.08–1.12 against his 3.25 (`Matlab_Sim/main_final.log`, `kiem_final_with_noise.log`, `kiem_enob_sweep.txt`). The replication explains the gap completely, in two parts.

### (a) On white noise, CR is set by how many FX16 LSBs the noise occupies

On a white-noise scene, DRHE's CR is fixed by one number: the noise standard deviation in FX16 LSBs. Because the scene is mostly empty cells, the scene content barely matters. `kr_early_result_check.m` (`results/early_result_check.txt`) runs Kiem's Table 3.2 scene with both FX16 scalings:

| FX16 scaling | NF (dBFS) | noise std (LSB) | DRHE, fixed dict | DRHE, R4S4 | LPC (slow time) | No prediction |
|---|---|---|---|---|---|---|
| hw (top 16 of 32 bits, Kiem's FFT core) | −70.7 | 33.4 | 1.57 | 2.07 | 1.73 | 1.71 |
| hw | −87.9 | 4.6 | **3.24** | **3.25** | 3.38 | 3.26 |
| peak (Matlab_Sim `compress_fx16`) | −70.7 | 133.4 | **1.12** | 1.64 | 1.20 | 1.19 |
| peak | −87.9 | 18.4 | 1.91 | 2.32 | 2.13 | 2.08 |

The row "peak, −70.7" **reproduces the early Matlab_Sim result (1.12 against 1.10–1.12)** in a completely independent code base. Two things produce the gap.

- **The FX16 scaling costs a factor of 4 (2 bits).** `compress_fx16` maps a full-scale sinusoid to 32767. Kiem's FFT IP core keeps the top 16 bits of a 32-bit word, where a full-scale sinusoid is only about 8191. The same noise therefore sits 4× higher in the 16-bit word, which costs about 2 bits per value.
- **The noise floor costs a factor of 7 (17 dB).** With Kiem's own scaling and white noise, CR 3.25 needs FX16 noise of about 4.6 LSB. That corresponds to NF ≈ −87.9 dBFS (full-scale sinusoid reference) or ≈ −99.9 dBFS (the "unit" reference). His stated −70.7 dBFS is 17 dB noisier and gives CR 1.57.

Together these put 133 LSB of noise where Kiem's CR implies about 5: roughly 30× more noise.

### (b) Kiem's own NF and CR cannot both hold under white noise

The replication cannot make his NF and his CR agree under white noise with any reading of his text. Two dBFS references were tried, and neither works: at CR 3.25 the NF comes out at −87.9 or −99.9 dBFS, never −70.7. His own dictionary gives independent evidence of the noise level his compressor saw.

Kiem built his fixed Huffman dictionary (Appendix A) from the S4 statistics of his real data [3.5.2]. A Huffman code is optimal only for the distribution it was built from. `kr_dictionary_fingerprint.m` (`results/dictionary_fingerprint.txt`) codes Gaussian residuals with his dictionary. The overhead against an ideal code is:

- 0.0 % at a residual std of 6–8 LSB;
- 10 % at 15 LSB;
- 26 % at 33 LSB, the residual his stated NF would give on white noise.

**His dictionary is the fingerprint of residuals of about 6–8 LSB, not 33.** That agrees with his CR of 3.25 and with his histograms (Figs. 3.9–3.10: "most values" within ±40).

The most likely reconciliation is his data. Table 3.5 is measured on **real** CTRX recordings: his §3.5.1–3.5.2 name data id = 1, and his FN of 0.59 % means about 170 reference detections. On real data the NF estimate ("the mean of the noisy part of the signal in dB" [3.4.2]) can be raised by clutter, leakage and sidelobes in the cells it averages, while most cells, which set the CR, sit much lower. A white-noise simulation has no such difference: the NF and the per-cell noise are the same number. So matching his NF in simulation forces far too much noise into every cell. This inference fits every number available. It cannot be confirmed without his data or code.

### (c) Why ColoRadar gives different numbers again

ColoRadar differs from Kiem's radar in ways that matter:

- **12-TX TDM.** Ramp *m−1* is a different transmitter 11 times in 12, so lag-1 prediction runs along the wrong axis. Predicting from ramp *m−12* fixes this (+13.3 % for DRHE).
- **Gain staging.** Only 9.8 of 16 bits carry information.
- **Scenes.** The scenes are dense and real.

`kr_tdm_experiment.m` (`results/tdm_experiment.txt`) shows where the TDM effect appears:

- **Kiem's sparse scene:** negligible (1.850 / 1.836 / 1.859 at −75 dBFS), because noise dominates.
- **Dense scene (300 scatterers):**
  - At −95 dBFS, prediction pays for itself: DRHE 3.40 against 1.95 without prediction.
  - TDM with lag 1 cuts DRHE to 2.37.
  - Lag 12 recovers part of the loss, to 2.56.

---

## 3. The replication

`run_kiem_replication.m` rebuilds Kiem's workflow [Fig. 3.1] from his text alone. It does not use Matlab_Sim. The chain is:

1. His Table 3.2 radar: 1 MMIC, **1 TX**, 4 RX, 1024 samples × 512 ramps, 14-bit ADC, and five targets at his range and Doppler bins and amplitudes.
2. The shift to 32-bit full scale, the Hanning window, FFT/N, and the first half of the spectrum.
3. The FP16 reference, FX16, the lossy schemes of his design space, DRHE (R4S4 with RLE, S4 only, and his fixed dictionary), [25]-style LPC-Huffman, and this thesis's slow-time LPC.
4. The Doppler FFT, NCI and peak detection.
5. FN, FP, NF and SNR against FP16.

Every lossless path is decoded and checked, not assumed.

**What it reproduces:**

- His DRHE pattern exactly. At the noise level where R4S4 gives 3.25, S4-only gives **3.24**, as in his Table 3.6.
- His finding that RLE adds almost nothing at that level (3.25 against 3.24).
- The fixed dictionary costing almost nothing there (3.23).
- Detection metrics for the lossless schemes that equal FX16's, by construction, as in his table.

**What it cannot reproduce:**

- His absolute numbers. Table 3.5 is measured on real data that we do not have.
- The lossy rows. CMPRA/B and EGE are proprietary and are approximated here (`kr_lossy.m`). Our scene's SNR is 60–74 dB, against his 22 dB. At that SNR a 3- or 7-bit mantissa creates quantisation spurs that the detector finds, so the FP percentages of those rows (e.g. CMPRB 13,980 %) describe this scene, not his.

**Assumptions** are marked `ASSUMPTION` in the code and listed in `README.md`:

- target angles;
- amplitude scaling (his amplitudes sum to 2.7 × full scale);
- the random seed;
- detector details;
- the LPC order of [25];
- the internals of the lossy schemes.

The noise sweep shows the whole picture (`fig_noise_sweep.png`):

- **Fixed-dictionary cap.** DRHE with the fixed dictionary cannot exceed 16/4 = 4 because its shortest code plus APPEND is 4 bits. It saturates at 3.92.
- **R4S4 near zero noise.** R4S4 with RLE shoots up as the noise vanishes (82 at −140 dBFS), because long runs of zeros appear. That regime is irrelevant to real radar.
- **Slow-time LPC.** It stays level with or slightly above DRHE from −95 dBFS upwards.
- **Raw-ADC LPC.** It stays below 1.8 everywhere.
- **Kiem's published point.** CR 3.25 at NF −70.7 sits 17 dB to the right of where any white-noise curve passes 3.25.

---

## 4. Is our DRHE Kiem's §3.5.3?

### Verification

`kr_crosscheck_matlabsim.m` (`results/crosscheck_matlabsim.txt`) runs two DRHE implementations on the same FX16 frames:

- the thesis's `Matlab_Sim/compress_drhe.m`;
- this folder's `kr_drhe_encode.m`, written from §3.5.3 alone.

The two give **identical residuals and identical bit counts** at both noise levels (18,186,374 and 10,370,342 bits, a difference of 0).

The HLS DRHE-1 agrees with `compress_drhe.m` on all 50 ColoRadar frames except for AXI padding (`phase2_matlab_vs_vitis_cr.csv`), and it is lossless in C-sim and RTL co-sim. So the chain Kiem §3.5.3 → our MATLAB → our HLS holds at every link.

### Line-by-line audit

| Element of Kiem §3.5.3 / §3.5.4 / §4.3.4 | Kiem | Our MATLAB (`compress_drhe.m`) | Our HLS DRHE-1 | Same? |
|---|---|---|---|---|
| Input | FX16 range-FFT, first N/2 bins, per RX, ramp by ramp | same | same (128-bit AXIS, 4 RX) | yes |
| Cartesian → polar | a = √(re²+im²), θ = atan2(im, re) | same (double) | same (float) | yes; precision below |
| Magnitude prediction, Eq. 3.5 | â[m] = αâ[m−1] + (1−α)a[m−1] | same | same | yes |
| Phase prediction, Eq. 3.6 | θ̂[m] = βθ̂[m−1] + (2−β)θ[m−1] − θ[m−2] | same | same | yes |
| Phase wrap | once into [−π, π] (Listing, §4.3.4) | same | same | yes |
| α, β | 0.6, 0.4 (Table 4.4) | same | same | yes |
| Polar → Cartesian | rounded to int16 (ap_fixed<16,16,AP_RND>) | round() | roundf() | yes |
| Difference, Eq. 3.7 | X − X̂ in 16-bit two's complement (default wrap mode) | `wrap_int16` | `wrap_int16` | yes |
| Model state | 5 arrays per RX × bin, initialised to zero (§3.5.4) | same | same, cleared at ramp 0 of every frame | yes; see (c) |
| State update | from the input sample (open loop, Fig. 3.16) | open loop | from the reconstructed sample (closed loop) | **changed**, (a) |
| RLE | removed (§3.5.1) | none | none | yes |
| S4 | region of Table 3.7, 0–15 | ⌊log₂\|v\|⌋+1, capped at 15 | same regions (lookup) | yes |
| APPEND | v for v > 0; v + 2^S4 − 1 for v < 0 | bits counted | same formula | yes |
| Residual −32768 | not representable (S4 = 15 spans ±[16384, 32767]); not addressed | counted as S4 = 15 (bit count only) | clamped to −32767 | **changed**, (a) |
| Huffman dictionary | fixed, Appendix A | same 16 lengths | same codes, bit-reversed for LSB-first packing | yes; see (d) |
| Arithmetic | fixed point: mag ap_ufixed<16,16>, phase ap_fixed<16,3>, intermediates ap_fixed<32,4> | double | float | **changed**, (b) |
| Output packing | 58-bit per-channel packets into 256-bit AXIS | bit count | 512-bit accumulator → 256-bit AXIS | layout only, (d) |
| Prediction lag | ramp m−1 (1 TX) | m−1 | m−1 (DRHE-1); m−n<sub>Tx</sub> (DRHE-n) | extension, (e) |

### The differences, and why each was made

**(a) Closed loop with the −32768 clamp: a defect fix.**

Kiem's Table 3.7 gives S4 = 15 the range ±[16384, 32767]. That is exactly 2¹⁵ values, which fill the 15 APPEND bits. A residual of −32768 therefore has **no code**. Worse, `get_append_bits(−32768, 15)` aliases onto the code for +32767. Kiem's text does not address this. It can happen: for example, re = −32768 with a prediction of 0, or a residual that wraps.

The HLS clamps that one residual to −32767, which costs at most 1 LSB on that sample and leaves the bitstream format unchanged. Once one sample has been clamped, an open-loop encoder would update its state from the original sample while the decoder updates from the clamped one. Because the IIR filters are recursive, the two would disagree for every remaining ramp. Updating the encoder from the reconstructed sample (closed loop) confines the error to the one sample.

When no clamp fires, the reconstructed sample equals the original, so the closed loop produces **bit-identical output to Kiem's open loop**. On ColoRadar the residuals span about [−514, +416], so it never fires. The edge-case testbench (`drhe_tb_edge.cpp`) exercises it deliberately.

The cost is hardware only: 26 cycles of pipeline depth in floating point, about 4 in fixed point (ablation ladder, step 5).

**(b) Floating-point arithmetic instead of Kiem's fixed point: a Thesis A choice, now shown to be unnecessary.**

Floating point was chosen so the HLS would match the MATLAB model exactly. Kiem notes (Ch. 5, Table 5.5) that his MATLAB could not be bit-accurate to his fixed-point HLS, which is why he needed an HLS decoder. The ablation ladder measured the cost and the benefit:

- the float design uses 2.06× the LUTs, 4.66× the FFs and 2× the BRAM of a fixed-point replica of his design, and 132 DSPs against his 44;
- it gains **0.065 %** of CR on the same frames.

The fixed-point side variant of DRHE-1 (20,549 LUT, 44 DSP, the same as Kiem's) is the better engineering choice, and it is recorded as future work.

**(c) State cleared at the start of every frame: a clarification, not a change.**

§3.5.4 says the model "is initialized with zero". Kiem's MATLAB decodes one frame at a time, so this is per frame. His HLS text does not say what happens between frames. DRHE-1 clears its state at ramp 0 of every frame, so every frame can be decoded on its own and a lost frame cannot corrupt the next. The one extra write per cycle is what costs II = 2 (HLS 200-885). Ladder step 3 clears by read instead and reaches II = 1.

**(d) Packer layout: same bits, different order.**

The Huffman codes and APPEND fields have the same lengths as Kiem's. The compressed size is therefore the same, apart from padding. The codes are stored bit-reversed because the packer shifts least-significant-bit first. The stream is thus not bit-compatible with a decoder written for Kiem's 58-bit packets, and it was never meant to be. The ladder (steps 1–2) measured the packer's cost at about 4,200 LUTs.

**(e) DRHE-n, predicting from ramp m−n<sub>Tx</sub>: an extension for TDM-MIMO.**

Kiem's radar has one transmitter, so ramp *m−1* is the previous observation of the same channel. ColoRadar interleaves 12 transmitters. DRHE-n indexes its state by transmitter so that each prediction comes from the same transmitter's previous ramp. With n<sub>Tx</sub> = 1 it is DRHE-1, and so it is Kiem's algorithm. On ColoRadar it is worth +13.3 % CR and costs 40 BRAM.

**Conclusion.** The prediction model, the encoding, the dictionary and the parameters are Kiem's §3.5.3, verified to the bit in MATLAB and against HLS. The changes are:

- one defect fix, the −32768 clamp with the closed loop, which changes nothing on real data;
- two implementation choices, float arithmetic and the packer layout, whose costs are measured in Chapter 7;
- one clarification, per-frame reset;
- one extension, lag n<sub>Tx</sub>, which reduces to his algorithm for his radar.

---

## Caveats

- **The scene is Kiem's simulated one; his headline table is real data.** The replication reproduces his *method* and his *DRHE pattern*, not his absolute numbers. The operating point that matches his CR is chosen, not predicted.
- **The NF/CR reconciliation in §2(b) is an inference.** It fits every number available: the CR, the dictionary fingerprint and the histograms. It cannot be confirmed without his data or code.
- **Some parameters are assumed.** [25]'s predictor order and coefficient format, and the lossy schemes' internals, are not published. Order 1–10 was swept, and both the autocorrelation and covariance methods were tried. Neither changes the conclusion at realistic noise.
- **Most runs use one random seed.** The noise sweep is smooth, so single-seed variation is small compared with the effects discussed.
