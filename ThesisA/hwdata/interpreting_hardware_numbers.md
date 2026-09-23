# Accounting for the hardware numbers (thesis report, Chapter 7)

This note summarises Chapter 7 of `thesis_report.tex`, "Accounting for the Hardware Numbers" (source `ch_interpret.tex`, which inputs `draft/lutff.tex` and `draft/master_summary.tex`). It was rewritten on 24 September 2026, after the full Vivado implementation and the Kiem ablation study. It replaces the earlier HLS-based version.

## What was run

- **Implementation.** Each design was taken through Vivado synthesis, placement and routing, out of context, on `xcku5p-ffvb676-2-e` at 10 ns.
  - Command: `vitis-run --mode hls --impl` with four extra cfg lines: `vivado.flow=impl`, `vivado.clock=10`, `vivado.report_level=2`, `vivado.max_timing_paths=10`.
  - Designs: DRHE-1, DRHE-n, LPC-1,2 and LPC-n,2n.
- **Replica of Kiem.** Kiem's design was rebuilt from his §4.3.4.
  - Fixed-point types: mag ap_ufixed<16,16>, phase ap_fixed<16,3>, intermediates ap_fixed<32,4>.
  - hls::sqrt, atan2, sin and cos in fixed point.
  - 58-bit per-channel packer, open loop, II=1.
- **Ablation ladder.** Five single-change steps lead from DRHE-1 to the replica, plus side variants.
  - Every variant is lossless in C-sim.
  - Step 3 is also lossless in RTL co-sim (35,909 cycles).
- **Where things live.**
  - Source: `hls_abl/<variant>` on the device; `abl/` in outputs.
  - Numbers: `collect_impl.py`, which writes `hw_numbers.json`, `\HW{tag}{key}` macros and the tables.

## Headline reversals (HLS estimate vs routed)

| | HLS estimate | Routed |
|---|---|---|
| DRHE-1 LUT | 115,534 | **35,343** (0.77x Kiem's 45,892) |
| DRHE-1 Fmax | 81.88 MHz | **135.5 MHz** (WNS 2.62 ns) |
| DRHE-n LUT / Fmax | 115,736 / 81.88 | **34,804 / 131.0** |
| LPC-1,2 LUT / Fmax | 80,528 / 85.43 | **29,772 / 118.6** |
| LPC-n LUT / Fmax | 86,298 / 85.43 | **34,503 / 106.3** (tightest, WNS 0.595) |

- Every main design meets 100 MHz. The claim "neither meets timing" and the advice to use a CORDIC to meet timing were wrong.
- DRHE fits Kiem's XCZU3CG at 49–50% of its LUTs, not 164%.
- LPC-n uses almost exactly as many LUTs as DRHE-n (0.99x). LPC-n's four integer dividers come from `m % HIST` and take 5,834 LUTs.
- Kiem's part is the **XCZU3CG**-SFVC784-1-e, not the ZU3EG.

## Ladder (routed, xcku5p-2)

| Step | Change | LUT | FF | DSP | BRAM18 | II | Depth |
|---|---|---|---|---|---|---|---|
| 0 | DRHE-1 | 35,343 | 23,546 | 132 | 40 | 2 | 58 |
| 1 | unsigned packer offset | 33,502 | 24,423 | 132 | 40 | 2 | 58 |
| 2 | Kiem 58-bit packer | 31,124 | 21,261 | 127 | 40 | 2 | 62 |
| 3 | clear state by read (II=1) | 52,432 | 30,373 | 264 | 40 | 1 | 59 |
| 4 | Kiem fixed point | 16,882 | 5,380 | 48 | 20 | 1 | 16 |
| 5 | open loop = replica | 17,141 | 5,050 | 48 | 20 | 1 | 12 |
| – | Kiem published | 45,892 | 9,243 | 44 | 20 | 1 | 23 |

The steps add up exactly.

| Side variant | LUT | FF | DSP | BRAM18 | II | Depth | Fmax |
|---|---|---|---|---|---|---|---|
| Fixed-point DRHE-1 (only arithmetic changed) | 20,549 (−42%) | 9,230 (−61%) | 44 (= Kiem) | 20 | 2 | 12 | 102.8 MHz (tight) |

## Every difference from Kiem and its cause

- **BRAM 2x:** 32-bit float state words, against 16-bit. The replica matches Kiem's 10 tiles exactly.
- **DSP 3x:** every DSP is a float operator (16 fmul x3, 12 fadd x2, 4 sin/cos x13, 2 atan2 x4).
  - It would be 6x (264) at II=1.
  - The ratio is 3x rather than 6x because II=2 lets two channels share each unit.
- **II 2 vs 1:** a reset write on r==0 means three accesses on two ports (HLS 200-885). Step 3, which reads instead of writing, reaches II=1.
- **Throughput:** measured throughput rises from 5.14 to 8.76 Gbit/s (+71%).
  - Kiem's 11.92 Gibit/s is theoretical: 12.8 Gbit/s = 128 bits x 100 MHz.
  - Theoretical against theoretical, the gap is exactly 2x.
  - The replica measures 11.54 Gbit/s.
- **Depth 58 vs 23:**
  - 26 cycles come from the closed loop. The open-loop float version is 32 deep.
  - The rest is float operator latency.
  - In fixed point the closed loop costs only 4 cycles and a few hundred FF.
- **LUT/FF, DRHE-1 against the replica (2.06x LUT, 4.66x FF):**
  - Float operators are 69% of LUTs and 54% of FF. The atan2 alone is 11,961 LUTs, a third of the design.
  - The packer costs about 4,200 LUTs.
  - The per-step costs come from the ladder.
- **Replica against Kiem's own build (2.68x LUT, 1.83x FF), tested:**
  - Speed grade −1: +548 FF (13% of the FF gap), 0% of the LUT gap.
  - Literal packer (four inserts, int offset): +1,435 LUT (5%), +1,164 FF (28%).
  - 23-cycle depth via a LATENCY pragma: +167 FF (4%).
  - Total explained: about 45% of the FF gap and about 5% of the LUT gap.
  - The rest is **unexplained**. Likely causes are the Vitis 2022.2 math library or undescribed or debug (ILA) logic. It was reported honestly rather than attributed.
- **Fmax:** all designs meet 100 MHz.
  - On the −1 grade the replica reaches 125.0 MHz (3.5% lower).
  - DRHE-1 on −1: 138.3 MHz. HLS schedules it deeper for the slower part (depth 63), so it meets Kiem's clock on his grade of silicon.
- **Power (vectorless):**
  - DRHE-1 draws 0.562 W dynamic, about 2x the replica, and uses about 4.4x the energy per frame.
  - Kiem reports no power.
- **CR:** Kiem's 3.17 was measured on different data, so it is not comparable.
  - The replica and the float design differ by 0.065% on the same 10 frames.

## Not changed from the earlier version

- The yardsticks.
- The latency taxonomy: pipeline, frame and added latency.
- The CR decomposition.
- The LPC scaling argument: at Kiem's frame size it would take about 53 ms and need a 67 Mbit buffer.

## Related updates

The following were updated with the routed numbers, the ladder and the Kiem ledger:

- Results pack: Table 7, new Table 9b and section 4b.
- `results_tables.txt`.
- Supervisor progress update: the hardware section, next steps, risks and the status figure.
