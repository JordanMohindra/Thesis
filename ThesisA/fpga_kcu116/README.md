# KCU116 hardware test of the DRHE and LPC compressors

This folder takes the HLS cores in `../hls_component` onto the AMD KCU116 board
(XCKU5P-2FFVB676E). The board streams every frame through the compressor and
times it. The LPC build also decompresses each frame on chip and checks it is
bit-exact. A PC script then checks the compressed bytes against the C simulation.

All of it has been built once on this PC (in `D:\Thesis\ThesisA\fpga_kcu116`):

| Output (in `out/`)  | What it is | Timing | Resources (of XCKU5P) |
|---|---|---|---|
| `kcu116_drhe.bit`, `.xsa`, `radar_app_drhe.elf` | DRHE lag-12 compressor (compress only) | WNS +0.395 ns, all met | 60,386 LUT (28 %), 104.5 BRAM, 138 DSP |
| `kcu116_lpc.bit`, `.xsa`, `radar_app_lpc.elf`   | LPC lags 12,24 compressor **and** decompressor | WNS +0.320 ns, all met | 86,621 LUT (40 %), 179.5 BRAM, 172 DSP |

**Why the DRHE build has no decompressor.** Synthesised on its own, the DRHE
decompressor takes about 182,000 LUTs. With the compressor and the rest of the
system, the design needs 235,750 LUTs, and the XCKU5P only has 216,960. Most of
that logic is the decoder's eight chained 512-bit variable shifts in each
pipeline iteration. So the DRHE board compresses only. Losslessness is then
proved on the PC: every compressed frame must be byte-identical to the C
simulation, whose bitstream is known to decode exactly
(`verify_indep/golden_check.py` decodes it independently). This is also the
realistic deployment, because the decompressor belongs on the central computer,
not at the sensor.

```
hls/      export_ips.bat     C-sim (writes golden output) + package the 4 cores as IP
vivado/   build.bat          block design -> bitstream + .xsa   (build_kcu116.tcl)
sw/       build_sw.bat       MicroBlaze program (src/main.c, src/board_map.h)
host/     make_frames.py     strips the header off coloradar_multiframe.bin
          run_board.bat      xsdb: program board, load frames, run, dump results
          compare_results.py checks the board run against the C simulation
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
 dma_d : DDR -> lpc_tdm_decompress    -> DDR     (LPC build only)
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
3. Quick test with 5 frames: `host\run_board.bat drhe 5`
4. `"C:\Program Files\Python311\python.exe" host\compare_results.py drhe`
5. Full run: `host\run_board.bat drhe 50`, then compare again.
6. Repeat steps 3–5 with `lpc`.

Loading frames over JTAG is slow (minutes for 50 frames). The UART shows one
line per frame, for example the first DRHE frame:

```
frame   comp bytes      CR   comp cyc  decomp cyc  maxdiff  status
    0       103712  3.7914      ~61000         n/a      n/a   OK
```

Expected results:

| Bitstream | Mean per-frame CR | Other |
|---|---|---|
| DRHE | 3.75082 | 50/50 frames byte-identical to C-sim |
| LPC | 3.69681 | MaxDiff 0 on every frame, bitstreams identical |

## Rebuilding from scratch

1. `hls\export_ips.bat` (about 20 min). This C-simulates both designs, writes
   `golden\`, and packages the 4 cores into `ip_repo\`.
2. `vivado\build.bat drhe`, then `vivado\build.bat lpc` (1–1.5 h each on this
   16 GB PC).
   * Arguments are `[ddr4_sdram_075|062] [jobs] [decomp=auto|0|1]`.
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
* **Status `0x00000020` on an LPC frame:** the decompressor stopped before reading all of the
  compressed data.
* **Vivado exits with -1073741819 right at the start:** this is a one-off crash. Run it again.
