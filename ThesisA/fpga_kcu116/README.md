# KCU116 hardware test of the DRHE and LPC compressors

The FPGA compresses and the PC decompresses, as in a vehicle where the sensor
compresses and the central computer decompresses. This folder takes the HLS
compressors in `../hls_component` onto the AMD KCU116 board
(XCKU5P-2FFVB676E):

1. The board streams every frame through the compressor and times it.
2. The PC reads the compressed frames back.
3. The PC decompresses them with `host/pc_decompress.bat`.
4. `host/compare_results.py` checks that every frame comes back bit-exact and
   that the compressed bytes match the C simulation.

Built on this PC (in `D:\Thesis\ThesisA\fpga_kcu116`):

| Output (in `out/`)  | What it is | Timing | Resources (of XCKU5P) |
|---|---|---|---|
| `kcu116_drhe.bit`, `.xsa`, `radar_app_drhe.elf` | DRHE lag-12 compressor, re-derived dictionary | WNS +0.243 ns, all met | 61,011 LUT (28 %), 104.5 BRAM, 138 DSP |
| `kcu116_lpc.bit`, `.xsa`, `radar_app_lpc.elf`   | LPC lags 12,24 compressor, re-derived dictionary | WNS +0.174 ns, all met | 59,203 LUT (27 %), 162.5 BRAM, 164 DSP |

Both bitstreams hold only the compressor (`.info` says `decomp 0`). The
resource figures cover the whole system: MicroBlaze, DDR4 controller, DMA
and compressor.

**PC decompressor.** `pc_decompress.bat` runs the same `*_tdm_decompress.cpp`
that was verified lossless in C simulation. It is compiled for the PC through
Vitis C simulation, so the floating-point maths uses the bit-accurate HLS
models. For DRHE this is essential: its predictor uses float
sqrt/atan2/sin/cos, and the decoder must repeat the encoder's arithmetic bit
for bit. An independent double-precision Python decoder
(`verify_indep/independent_decode.py`) is exact for LPC but drifts by 1–6 LSB
on 8 of the 50 DRHE frames.

**Why not decompress on the FPGA?** It can be done for experiments
(`vivado\build.bat <algo> ... 1`), but for DRHE it does not fit. The DRHE
decompressor alone synthesises to about 182,000 LUTs, and compressor plus
decompressor need 235,750 against the 216,960 the XCKU5P has.

```
hls/      export_ips.bat     C-sim (writes golden output) + package the 4 cores as IP
vivado/   build.bat          block design -> bitstream + .xsa   (build_kcu116.tcl)
sw/       build_sw.bat       MicroBlaze program (src/main.c, src/board_map.h)
host/     make_frames.py     strips the header off coloradar_multiframe.bin
          run_board.bat      xsdb: program board, load frames, run, dump results
          pc_decompress.bat  decompresses the board's output on the PC (HLS C++ via C-sim)
          compare_results.py checks the board run: PC-decompressed == original,
                             compressed bytes == C simulation
out/      bitstreams, .xsa, .elf, frames_N.bin        (generated)
golden/   C-simulation compressed streams             (generated)
results/  board outputs                               (generated)
```

Vitis refuses paths that contain spaces, so work from a copy such as
`D:\Thesis\ThesisA\fpga_kcu116` with `hls_component` next to it. Set
`XILINX_ROOT` if the tools are not in `D:\Xilinx\2026.1`.

## What runs on the board

```
 MicroBlaze (128 KB local RAM) --AXI--+-- DDR4 1 GB @ 0x8000_0000 (DDR4-2400)
                                      +-- UART Lite 115200 (CP2105 UART1), timer, LEDs
                                      +-- control registers of the DMAs and cores
 dma_c : DDR -> <algo>_tdm_compress   -> DDR     (128-bit in, 256-bit out)
 Everything runs at 100 MHz.
```

DDR layout:

| Contents | Address |
|---|---|
| Frames | `0x9000_0000` |
| Compressed frame *f* | `0xA000_0000 + f·1 MiB` |
| Reconstructed frames | `0xB000_0000` |
| Results | `0xBF00_0000` |
| Mailbox | `0xBF10_0000` |

## Running it (the board part)

1. Connect the board: 12 V power, one micro-USB cable to the JTAG port and
   one to the USB-UART port. Switch it on.
2. Open a serial terminal (PuTTY or Tera Term) at 115200 8N1 on the CP2105
   COM port that is wired to the FPGA. That is UART1, the "Standard" port of
   the two the CP2105 creates. If you see nothing, try the other one.
3. In a command prompt, `cd /d D:\Thesis\ThesisA\fpga_kcu116\host` and run a
   quick 5-frame test:
   ```
   run_board.bat drhe 5          (FPGA compresses; results copied to the PC)
   pc_decompress.bat drhe        (PC decompresses, ~2 min)
   "C:\Program Files\Python311\python.exe" compare_results.py drhe
   ```
4. Full run: the same three commands with `50` frames.
5. Repeat steps 3–4 with `lpc`.

Loading frames over JTAG is slow (minutes for 50 frames). Expected results:

| Bitstream | Mean per-frame CR | Check |
|---|---|---|
| DRHE | 4.21704 | every frame exact after PC decompression, bitstreams identical to C-sim |
| LPC | 4.40345 | the same |

Both cores use the **re-derived Huffman dictionaries** from the thesis report
(code lengths in `verify_indep/retrain_complete.json`: `drhe12` for DRHE,
`lpc1224` for LPC; trained on frames 0-4, so quote frames 5-49 as the held-out
result: 4.2066 and 4.3710). With Kiem's original Appendix A table the same
designs gave 3.75082 and 3.69681; those board runs (7 Oct 2026) are the
Kiem-dictionary baseline. The tables are `DRHE_TDM_HUFFMAN_TABLE` in
`hls_component/drhe_tdm_common.h` and `LPC_TDM_HUFFMAN_TABLE` in
`lpc_tdm_common.h`; compressor and decompressor read the same table.

The decompression step was tested on this PC by using the C-simulation
streams as stand-ins for the board's output: 50/50 frames exact for both
algorithms.

## Rebuilding from scratch

1. `hls\export_ips.bat` (about 20 min). This C-simulates both designs, writes
   `golden\`, and packages the 4 cores into `ip_repo\`.
2. `vivado\build.bat drhe`, then `vivado\build.bat lpc` (1–1.5 h each on this
   16 GB PC).
   * Arguments are `[ddr4_sdram_075|062] [jobs] [decomp=0|1]`.
   * Keep jobs at 2–3. With 8 jobs the PC ran out of memory and the build
     stalled.
3. `sw\build_sw.bat drhe` and `sw\build_sw.bat lpc`.
4. `python host\make_frames.py ..\hls_component\coloradar_multiframe.bin 50`
   (and again with `5`).

## If something goes wrong

* **The UART stays silent and the LEDs stay off:** DDR4 calibration has probably failed. The
  build uses the board file's -075E memory part. If that fails on your board,
  rebuild with `vivado\build.bat <algo> ddr4_sdram_062`. The part number is
  printed on the memory chips.
* **`no targets found with name =~ "xcku5p*"`:** the JTAG cable has not been detected. Check the
  power and the JTAG USB cable. If Windows does not list a Digilent USB device,
  install the cable drivers (Vivado installer, cable drivers option).
* **"No valid frame count in the mailbox":** the program was started without
  `run_board.tcl`.
* **Vivado exits with -1073741819 right at the start:** this is a one-off crash. Run it again.
