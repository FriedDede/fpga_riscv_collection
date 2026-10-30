// VeeR-EL2 u55c smoke test: uart, stack in DCCM, DCCM through the DMA port, I$ hits on DRAM code.
// Returns 1 on success, 0x100 | failed checks mask otherwise (written to tohost by crt0).
#include <stdint.h>
#include "uart.h"
#include "platform.h"

#define DCCM_BASE   0xF0040000u
#define DCCM_END    0xF0050000u
// the DCCM is also reachable through the VeeR DMA port alias
#define DMA_ALIAS(addr) ((addr) & 0x7FFFFFFFu)

static inline uint32_t read_sp(void)
{
    uint32_t sp;
    asm volatile ("mv %0, sp" : "=r"(sp));
    return sp;
}

// recursion with a local array: all the traffic goes to the DCCM stack
static uint32_t stack_sum(uint32_t n)
{
    volatile uint32_t buf[8];
    uint32_t s = 0;
    for (int i = 0; i < 8; i++) buf[i] = n + i;
    for (int i = 0; i < 8; i++) s += buf[i];
    return n == 0 ? s : s + stack_sum(n - 1);
}

static uint32_t check_dccm(void)
{
    uint32_t sp = read_sp();
    if (sp < DCCM_BASE || sp >= DCCM_END) return 1;
    // sum over n = 0..15 of (8n + 28)
    if (stack_sum(15) != 8 * 120 + 16 * 28) return 1;
    // the same DCCM word read through the DMA alias
    volatile uint32_t *word = (volatile uint32_t *)(DCCM_BASE + 0x8000);
    *word = 0xC0FFEE00u;
    return *(volatile uint32_t *)DMA_ALIAS(DCCM_BASE + 0x8000) == 0xC0FFEE00u ? 0 : 1;
}

static uint32_t check_icache(void)
{
    uint32_t hits, misses;
    asm volatile ("csrw 0x323, %0" :: "r"(2));     // mhpmevent3 = I$ hit
    asm volatile ("csrw 0x324, %0" :: "r"(3));     // mhpmevent4 = I$ miss
    asm volatile ("csrw 0xb03, zero");
    asm volatile ("csrw 0xb04, zero");
    asm volatile ("csrw 0x320, zero");             // mcountinhibit: count everything
    volatile uint32_t acc = 0;
    for (int i = 0; i < 64; i++) acc += i;         // loop body runs from DRAM, cacheable
    asm volatile ("csrr %0, 0xb03" : "=r"(hits));
    asm volatile ("csrr %0, 0xb04" : "=r"(misses));
    print_uart("I$ hits 0x");
    print_uart_int(hits);
    print_uart(" misses 0x");
    print_uart_int(misses);
    print_uart("\n");
    return (acc == 2016 && hits > misses) ? 0 : 1;
}

static uint32_t check_dram(void)
{
    static volatile uint32_t data[16];
    for (int i = 0; i < 16; i++) data[i] = 0xA5A50000u | i;
    for (int i = 0; i < 16; i++)
        if (data[i] != (0xA5A50000u | i)) return 1;
    return 0;
}

int main(void)
{
    uint32_t fail = 0;
    init_uart(CORE_CLK, UART_BAUD);
    print_uart("VeeR-EL2 u55c\n");

    fail |= check_dccm()   << 0;
    fail |= check_icache() << 1;
    fail |= check_dram()   << 2;

    print_uart(fail ? "FAIL 0x" : "PASS 0x");
    print_uart_int(fail);
    print_uart("\n");
    // wait for the uart transmitter to be empty before ending the test
    while (!(*(volatile uint8_t *)(UART_LINE_STATUS) & 0x40)) {}
    return fail ? (0x100 | fail) : 1;
}
