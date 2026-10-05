/* board_map.h - fixed address map of the KCU116 test system.
 * Must match the assign_bd_address lines in ../../vivado/build_kcu116.tcl. */
#ifndef BOARD_MAP_H
#define BOARD_MAP_H

#include <stdint.h>

/* ---- peripherals ---------------------------------------------------- */
#define GPIO_LED_BASE   0x40000000u
#define UART_BASE       0x40600000u
#define TIMER_BASE      0x41C00000u
#define DMA_C_BASE      0x41E00000u   /* feeds the compressor            */
#define DMA_D_BASE      0x41E10000u   /* feeds the decompressor          */
#define COMP_BASE       0x44A00000u   /* <algo>_tdm_compress  s_axi_control */
#define DECOMP_BASE     0x44A10000u   /* <algo>_tdm_decompress s_axi_control */

/* ---- DDR4 (1 GB at 0x8000_0000) --------------------------------------
 * The bottom of DDR is left free in case the linker places code there.   */
#define DDR_BASE        0x80000000u
#define IN_BASE         0x90000000u   /* frames, back to back (host loads)  */
#define COMP_OUT_BASE   0xA0000000u   /* compressed frame f at + f*COMP_SLOT */
#define COMP_SLOT       0x00100000u   /* 1 MiB per frame (worst case ~655 KB) */
#define RECON_BASE      0xB0000000u   /* reconstructed frames, back to back */
#define RESULT_BASE     0xBF000000u   /* per-frame result records           */
#define MBOX_BASE       0xBF100000u   /* host <-> MicroBlaze mailbox        */

/* mailbox words (32-bit, offsets in words) */
#define MBOX_NFRAMES    0   /* written by host before 'con'                 */
#define MBOX_STATUS     1   /* MicroBlaze: 0xB007B007 running, 0xD0D0D0D0 done */
#define MBOX_DONE_CNT   2   /* frames finished so far                       */
#define MBOX_VERSION    4
#define MBOX_FLAGS      5   /* written by host: bit0 = decompressor present */
#define FLAG_HAS_DECOMP 0x1u
#define MAXDIFF_NA      0xFFFFFFFFu  /* max_diff when there is no on-chip decompressor */
#define STATUS_RUNNING  0xB007B007u
#define STATUS_DONE     0xD0D0D0D0u
#define FW_VERSION      0x00010000u

/* one result record per frame, 8 words = 32 bytes */
typedef struct {
    uint32_t frame;
    uint32_t comp_bytes;      /* bytes the compressor produced (S2MM count) */
    uint32_t comp_cycles;     /* 100 MHz cycles, DMA start -> S2MM complete */
    uint32_t decomp_cycles;
    uint32_t max_diff;        /* max |reconstructed - original| over int16s */
    uint32_t mismatches;      /* number of int16 values that differ         */
    uint32_t status;          /* 0 = ok, otherwise ERR_* bits                */
    uint32_t reserved;
} result_t;

#define ERR_COMP_TIMEOUT    0x01u
#define ERR_DECOMP_TIMEOUT  0x02u
#define ERR_DMA_C           0x04u
#define ERR_DMA_D           0x08u
#define ERR_RECON_LEN       0x10u
#define ERR_MM2S_LEFTOVER   0x20u

/* ---- frame geometry (ColoRadar, 4 RX to hardware) -------------------- */
#define N_SAMPLES   128
#define N_RAMPS     192
#define N_RX        4
#define N_TX        12
#define FRAME_BYTES (N_SAMPLES * N_RAMPS * N_RX * 4u)   /* 393,216 */
#define MAX_FRAMES  50

/* ---- AXI DMA (simple mode) register offsets --------------------------- */
#define DMA_MM2S_CR     0x00
#define DMA_MM2S_SR     0x04
#define DMA_MM2S_SA     0x18
#define DMA_MM2S_SA_MSB 0x1C
#define DMA_MM2S_LEN    0x28
#define DMA_S2MM_CR     0x30
#define DMA_S2MM_SR     0x34
#define DMA_S2MM_DA     0x48
#define DMA_S2MM_DA_MSB 0x4C
#define DMA_S2MM_LEN    0x58
#define DMA_CR_RS       0x00000001u
#define DMA_CR_RESET    0x00000004u
#define DMA_SR_HALTED   0x00000001u
#define DMA_SR_IDLE     0x00000002u
#define DMA_SR_ERR_MASK 0x00000770u    /* Int/Slv/Dec errors, SG errors */
#define DMA_SR_IOC      0x00001000u

/* ---- Vitis HLS ap_ctrl_hs block (s_axi_control) ----------------------- */
#define AP_CTRL         0x00
#define AP_START        0x01u
#define AP_DONE         0x02u
#define AP_IDLE         0x04u
#define ARG_NSAMPLES    0x10
#define ARG_NRAMPS      0x18
#define ARG_NRX         0x20
#define ARG_NTX         0x28

/* ---- AXI Timer 0 ------------------------------------------------------ */
#define TMR_TCSR0       0x00
#define TMR_TLR0        0x04
#define TMR_TCR0        0x08
#define TMR_ENT0        0x080u
#define TMR_LOAD0       0x020u
#define TMR_ARHT0       0x010u

/* ---- UART Lite -------------------------------------------------------- */
#define UART_TX         0x04
#define UART_STAT       0x08
#define UART_TX_FULL    0x08u

/* ---- GPIO (LEDs) ------------------------------------------------------- */
#define GPIO_DATA       0x00
#define GPIO_TRI        0x04

#endif
