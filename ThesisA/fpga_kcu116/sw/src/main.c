/* =========================================================================
 *  main.c - MicroBlaze test program for the KCU116 compressor test system
 *
 *  For every frame the host has loaded into DDR:
 *    1. stream it through <algo>_tdm_compress   (dma_c), timing it
 *    2. stream the result through <algo>_tdm_decompress (dma_d), timing it
 *    3. compare the reconstruction with the original, word by word
 *    4. write a result record to DDR and print a line on the UART
 *
 *  The same program serves the DRHE and the LPC bitstreams: both designs use
 *  the same address map and the same core interface (ap_ctrl_hs + 4 args).
 *  The DRHE bitstream has no on-chip decompressor (it does not fit next to the
 *  compressor on the XCKU5P); the host says so in MBOX[FLAGS] and steps 2-3
 *  are skipped - the host then checks the compressed bytes instead.
 *
 *  Host protocol (see ../../host/run_board.tcl):
 *    host loads frames at IN_BASE, writes MBOX[NFRAMES], then lets this run.
 *    MBOX[STATUS] goes RUNNING -> DONE; MBOX[DONE_CNT] counts frames.
 *
 *  Uses direct register access only, so it needs nothing from the BSP beyond
 *  the C runtime (no xil_printf, no driver APIs).
 * ========================================================================= */
#include <stdint.h>
#include "board_map.h"

#define REG(base, off)  (*(volatile uint32_t *)((uintptr_t)(base) + (off)))

/* -------------------------------------------------------------- UART -- */
static void uart_putc(char c)
{
    while (REG(UART_BASE, UART_STAT) & UART_TX_FULL) { }
    REG(UART_BASE, UART_TX) = (uint32_t)(unsigned char)c;
}
static void puts_(const char *s)
{
    while (*s) { if (*s == '\n') uart_putc('\r'); uart_putc(*s++); }
}
static void putu(uint32_t v)                  /* unsigned decimal */
{
    char b[12]; int i = 0;
    do { b[i++] = (char)('0' + v % 10u); v /= 10u; } while (v);
    while (i) uart_putc(b[--i]);
}
static void putu_w(uint32_t v, int w)         /* right-aligned */
{
    uint32_t t = v; int d = 1;
    while (t >= 10u) { t /= 10u; d++; }
    while (d++ < w) uart_putc(' ');
    putu(v);
}
static void puthex(uint32_t v)
{
    puts_("0x");
    for (int s = 28; s >= 0; s -= 4) uart_putc("0123456789ABCDEF"[(v >> s) & 0xF]);
}
static void put_fixed4(uint32_t x10000)       /* prints x/10000 with 4 decimals */
{
    putu(x10000 / 10000u); uart_putc('.');
    uint32_t f = x10000 % 10000u;
    uart_putc((char)('0' + f / 1000u)); uart_putc((char)('0' + (f / 100u) % 10u));
    uart_putc((char)('0' + (f / 10u) % 10u)); uart_putc((char)('0' + f % 10u));
}

/* ------------------------------------------------------------- timer -- */
static void timer_init(void)
{
    REG(TIMER_BASE, TMR_TCSR0) = 0;
    REG(TIMER_BASE, TMR_TLR0)  = 0;
    REG(TIMER_BASE, TMR_TCSR0) = TMR_LOAD0;                 /* load 0      */
    REG(TIMER_BASE, TMR_TCSR0) = TMR_ENT0 | TMR_ARHT0;      /* run, up     */
}
static inline uint32_t now(void) { return REG(TIMER_BASE, TMR_TCR0); }

/* --------------------------------------------------------------- DMA -- */
static void dma_init(uint32_t base)
{
    REG(base, DMA_MM2S_CR) = DMA_CR_RESET;
    while (REG(base, DMA_MM2S_CR) & DMA_CR_RESET) { }       /* resets both */
    REG(base, DMA_MM2S_CR) = DMA_CR_RS;
    REG(base, DMA_S2MM_CR) = DMA_CR_RS;
}
static void dma_clear_ioc(uint32_t base)
{
    REG(base, DMA_MM2S_SR) = DMA_SR_IOC;
    REG(base, DMA_S2MM_SR) = DMA_SR_IOC;
}
/* wait for the IOC bit on one channel; returns 0 on success, 1 on timeout */
static int wait_ioc(uint32_t base, uint32_t sr_off, uint32_t t0, uint32_t limit, uint32_t *t_end)
{
    for (;;) {
        uint32_t sr = REG(base, sr_off);
        if (sr & DMA_SR_IOC) { if (t_end) *t_end = now(); return 0; }
        if (sr & DMA_SR_ERR_MASK) return 2;
        if (now() - t0 > limit) return 1;
    }
}

/* --------------------------------------------------------- HLS core -- */
static void core_set_args(uint32_t base)
{
    REG(base, ARG_NSAMPLES) = N_SAMPLES;
    REG(base, ARG_NRAMPS)   = N_RAMPS;
    REG(base, ARG_NRX)      = N_RX;
    REG(base, ARG_NTX)      = N_TX;
}
static int core_check(uint32_t base, const char *name)
{
    core_set_args(base);
    int ok = REG(base, ARG_NSAMPLES) == N_SAMPLES && REG(base, ARG_NRAMPS) == N_RAMPS &&
             REG(base, ARG_NRX) == N_RX && REG(base, ARG_NTX) == N_TX &&
             (REG(base, AP_CTRL) & AP_IDLE);
    puts_("  "); puts_(name); puts_(ok ? ": registers OK, idle\n" : ": REGISTER CHECK FAILED\n");
    return ok;
}
static int wait_idle(uint32_t base, uint32_t limit)
{
    uint32_t t0 = now();
    while (!(REG(base, AP_CTRL) & AP_IDLE)) if (now() - t0 > limit) return 1;
    return 0;
}

static void led(uint32_t v) { REG(GPIO_LED_BASE, GPIO_DATA) = v; }

/* --------------------------------------------------------------- main -- */
#define TIMEOUT_CYC 100000000u   /* 1 s at 100 MHz; a frame takes < 5 ms */

int main(void)
{
    volatile uint32_t *mbox = (volatile uint32_t *)MBOX_BASE;
    volatile result_t *res  = (volatile result_t *)RESULT_BASE;

    REG(GPIO_LED_BASE, GPIO_TRI) = 0;     /* all LED pins outputs */
    led(0x01);
    timer_init();

    puts_("\n==============================================\n");
    puts_(" KCU116 radar compressor test  (fw ");
    puthex(FW_VERSION); puts_(")\n");
    puts_(" 128 bins x 192 ramps x 4 RX, nTx = 12\n");
    puts_("==============================================\n");

    mbox[MBOX_STATUS]   = STATUS_RUNNING;
    mbox[MBOX_DONE_CNT] = 0;
    mbox[MBOX_VERSION]  = FW_VERSION;

    uint32_t nframes = mbox[MBOX_NFRAMES];
    if (nframes == 0 || nframes > MAX_FRAMES) {
        puts_("No valid frame count in the mailbox (");
        puthex(nframes);
        puts_("). Load frames and write MBOX[0] from xsdb - see host/run_board.tcl.\n");
        mbox[MBOX_STATUS] = STATUS_DONE;
        led(0xAA);
        for (;;) { }
    }

    const int has_decomp = (mbox[MBOX_FLAGS] & FLAG_HAS_DECOMP) != 0;
    puts_(has_decomp ? " on-chip decompressor: yes\n" : " on-chip decompressor: no (compress only; host checks the bitstream)\n");
    int ok = core_check(COMP_BASE, "compressor  ");
    if (has_decomp) ok &= core_check(DECOMP_BASE, "decompressor");
    if (!ok) { mbox[MBOX_STATUS] = STATUS_DONE; led(0xF0); for (;;) { } }
    dma_init(DMA_C_BASE);
    if (has_decomp) dma_init(DMA_D_BASE);

    puts_("\nframe   comp bytes      CR   comp cyc  decomp cyc  maxdiff  status\n");

    uint64_t sum_in = 0, sum_out = 0;
    uint32_t worst_diff = 0, n_bad = 0, sum_cr_x10000 = 0;

    for (uint32_t f = 0; f < nframes; f++) {
        uint32_t in_addr  = IN_BASE + f * FRAME_BYTES;
        uint32_t c_addr   = COMP_OUT_BASE + f * COMP_SLOT;
        uint32_t r_addr   = RECON_BASE + f * FRAME_BYTES;
        uint32_t st = 0, t0, t1 = 0, t2 = 0, t3 = 0;
        uint32_t comp_bytes = 0, recon_bytes = 0;
        int e;

        led(0x80u | (f & 0x3Fu));

        /* ---------------- compress ---------------- */
        dma_clear_ioc(DMA_C_BASE);
        core_set_args(COMP_BASE);
        REG(DMA_C_BASE, DMA_S2MM_DA)     = c_addr;          /* arm receive  */
        REG(DMA_C_BASE, DMA_S2MM_DA_MSB) = 0;
        REG(DMA_C_BASE, DMA_S2MM_LEN)    = COMP_SLOT;
        REG(COMP_BASE, AP_CTRL)          = AP_START;
        t0 = now();
        REG(DMA_C_BASE, DMA_MM2S_SA)     = in_addr;         /* send frame   */
        REG(DMA_C_BASE, DMA_MM2S_SA_MSB) = 0;
        REG(DMA_C_BASE, DMA_MM2S_LEN)    = FRAME_BYTES;
        e = wait_ioc(DMA_C_BASE, DMA_S2MM_SR, t0, TIMEOUT_CYC, &t1);
        if (e) st |= (e == 1) ? ERR_COMP_TIMEOUT : ERR_DMA_C;
        if (wait_ioc(DMA_C_BASE, DMA_MM2S_SR, t0, TIMEOUT_CYC, 0)) st |= ERR_DMA_C;
        if (wait_idle(COMP_BASE, TIMEOUT_CYC)) st |= ERR_COMP_TIMEOUT;
        comp_bytes = REG(DMA_C_BASE, DMA_S2MM_LEN);
        if (st) dma_init(DMA_C_BASE);

        /* ---------------- decompress ---------------- */
        if (has_decomp && !st && comp_bytes > 0) {
            dma_clear_ioc(DMA_D_BASE);
            core_set_args(DECOMP_BASE);
            REG(DMA_D_BASE, DMA_S2MM_DA)     = r_addr;
            REG(DMA_D_BASE, DMA_S2MM_DA_MSB) = 0;
            REG(DMA_D_BASE, DMA_S2MM_LEN)    = FRAME_BYTES;
            REG(DECOMP_BASE, AP_CTRL)        = AP_START;
            t2 = now();
            REG(DMA_D_BASE, DMA_MM2S_SA)     = c_addr;
            REG(DMA_D_BASE, DMA_MM2S_SA_MSB) = 0;
            REG(DMA_D_BASE, DMA_MM2S_LEN)    = comp_bytes;
            e = wait_ioc(DMA_D_BASE, DMA_S2MM_SR, t2, TIMEOUT_CYC, &t3);
            if (e) st |= (e == 1) ? ERR_DECOMP_TIMEOUT : ERR_DMA_D;
            if (wait_idle(DECOMP_BASE, TIMEOUT_CYC)) st |= ERR_DECOMP_TIMEOUT;
            /* the decompressor must have consumed every compressed word */
            if (wait_ioc(DMA_D_BASE, DMA_MM2S_SR, t2, 1000000u, 0)) st |= ERR_MM2S_LEFTOVER;
            recon_bytes = REG(DMA_D_BASE, DMA_S2MM_LEN);
            if (recon_bytes != FRAME_BYTES) st |= ERR_RECON_LEN;
            if (st) dma_init(DMA_D_BASE);
        }

        /* ---------------- compare ---------------- */
        uint32_t maxd = has_decomp ? 0 : MAXDIFF_NA, nmis = 0;
        if (has_decomp && !(st & (ERR_COMP_TIMEOUT | ERR_DMA_C))) {
            volatile const uint32_t *a = (volatile const uint32_t *)(uintptr_t)in_addr;
            volatile const uint32_t *b = (volatile const uint32_t *)(uintptr_t)r_addr;
            for (uint32_t i = 0; i < FRAME_BYTES / 4u; i++) {
                uint32_t x = a[i], y = b[i];
                if (x != y) {
                    int32_t d0 = (int32_t)(int16_t)(x & 0xFFFF) - (int32_t)(int16_t)(y & 0xFFFF);
                    int32_t d1 = (int32_t)(int16_t)(x >> 16)    - (int32_t)(int16_t)(y >> 16);
                    if (d0) { nmis++; if (d0 < 0) d0 = -d0; if ((uint32_t)d0 > maxd) maxd = (uint32_t)d0; }
                    if (d1) { nmis++; if (d1 < 0) d1 = -d1; if ((uint32_t)d1 > maxd) maxd = (uint32_t)d1; }
                }
            }
        }

        res[f].frame         = f;
        res[f].comp_bytes    = comp_bytes;
        res[f].comp_cycles   = t1 - t0;
        res[f].decomp_cycles = t3 - t2;
        res[f].max_diff      = maxd;
        res[f].mismatches    = nmis;
        res[f].status        = st;
        res[f].reserved      = 0x5EC0DE00u;

        uint32_t cr = comp_bytes ? (uint32_t)(((uint64_t)FRAME_BYTES * 10000u + comp_bytes / 2u) / comp_bytes) : 0;
        putu_w(f, 5); putu_w(comp_bytes, 13); puts_("  "); put_fixed4(cr);
        putu_w(t1 - t0, 11);
        if (has_decomp) { putu_w(t3 - t2, 12); putu_w(maxd, 9); }
        else            { puts_("         n/a      n/a"); }
        puts_("   "); if (st) puthex(st); else puts_((has_decomp && maxd) ? "DIFF" : "OK");
        puts_("\n");

        if (!st) { sum_in += FRAME_BYTES; sum_out += comp_bytes; sum_cr_x10000 += cr; }
        if (st || (has_decomp && maxd)) n_bad++;
        if (has_decomp && maxd > worst_diff) worst_diff = maxd;
        mbox[MBOX_DONE_CNT] = f + 1;
    }

    puts_("\nframes: "); putu(nframes); puts_("   bad: "); putu(n_bad);
    puts_("   worst maxdiff: "); putu(worst_diff); puts_("\n");
    if (sum_out) {
        puts_("mean per-frame CR: "); put_fixed4((sum_cr_x10000 + (nframes - n_bad) / 2u) / (nframes - n_bad ? nframes - n_bad : 1));
        puts_("   aggregate CR: ");
        put_fixed4((uint32_t)((sum_in * 10000u + sum_out / 2u) / sum_out));
        puts_("\n");
    }
    if (!has_decomp) puts_(n_bad ? "RESULT: FAIL\n" : "RESULT: compressed every frame - run compare_results.py to check the bytes\n");
    else puts_(n_bad ? "RESULT: FAIL\n" : "RESULT: PASS - every frame bit-exact\n");

    mbox[MBOX_STATUS] = STATUS_DONE;
    led(n_bad ? 0x0F : 0xFF);
    for (;;) { }
    return 0;
}
