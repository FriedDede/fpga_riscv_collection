// CVA6 u55c smoke test: uart, 64 bit integer mul/div, fpu (with div/sqrt), DRAM accesses through
// the write-through D$, I$ and D$ hits on DRAM code and data.
// Returns 1 on success, 0x100 | failed checks mask otherwise (written to tohost by crt0).
#include <stdint.h>
#include "uart.h"
#include "platform.h"

static uint32_t check_muldiv(void)
{
    volatile int64_t a = -123456789012LL, b = 678;
    volatile uint64_t ua = 0xFFFFFFFFFFFFFFF0ull, ub = 7;
    if (a * b != -83703702950136LL) return 1;
    if (a / b != -182089659 || a % b != -210) return 1;
    if (ua / ub != 2635249153387078800ull || ua % ub != 0) return 1;
    // mulhu
    if ((uint64_t)(((unsigned __int128)ua * ub) >> 64) != 6) return 1;
    // 32 bit ops (mulw, divw)
    volatile int32_t c = -12345, d = 678;
    return (c * d == -8369910 && c / d == -18) ? 0 : 1;
}

static uint32_t check_fpu(void)
{
    volatile double a = 1.5, b = 2.25, c = -0.75;
    volatile float  fa = 3.0f, fb = 0.5f;
    if (a * b + c != 2.625) return 1;           // fmadd.d
    if (b / a != 1.5) return 1;                 // fdiv.d
    double r;
    asm volatile ("fsqrt.d %0, %1" : "=f"(r) : "f"(b));
    if (r != 1.5) return 1;                     // fsqrt.d
    if ((long)(a * 1000.0) != 1500) return 1;   // fcvt.l.d
    if ((double)(fa * fb + fa) != 4.5) return 1; // single precision, fcvt.d.s
    if (!(c < a) || (a == b)) return 1;         // compares
    return 0;
}

static uint32_t check_dram(void)
{
    static volatile uint64_t data[64];
    for (int i = 0; i < 64; i++) data[i] = 0xA5A5A5A500000000ull | i;
    for (int i = 0; i < 64; i++)
        if (data[i] != (0xA5A5A5A500000000ull | i)) return 1;
    // byte, halfword and word stores
    volatile uint8_t *b = (volatile uint8_t *)data;
    b[1] = 0x11; ((volatile uint16_t *)data)[1] = 0x2233; ((volatile uint32_t *)data)[1] = 0x44556677u;
    return data[0] == 0x4455667722331100ull ? 0 : 1;
}

static uint32_t check_caches(void)
{
    uint64_t c0, c1, c2;
    volatile uint64_t acc = 0;
    // the second run of the same loop hits in the I$ and D$: it must not be slower
    asm volatile ("csrr %0, mcycle" : "=r"(c0));
    for (int i = 0; i < 64; i++) acc += i;
    asm volatile ("csrr %0, mcycle" : "=r"(c1));
    for (int i = 0; i < 64; i++) acc += i;
    asm volatile ("csrr %0, mcycle" : "=r"(c2));
    print_uart("loop cycles 0x");
    print_uart_int(c1 - c0);
    print_uart(" 0x");
    print_uart_int(c2 - c1);
    print_uart("\n");
    return (acc == 2 * 2016 && (c2 - c1) <= (c1 - c0)) ? 0 : 1;
}

int main(void)
{
    uint32_t fail = 0;
    init_uart(CORE_CLK, UART_BAUD);
    print_uart("CVA6 u55c\n");

    fail |= check_muldiv() << 0;
    fail |= check_fpu()    << 1;
    fail |= check_dram()   << 2;
    fail |= check_caches() << 3;

    print_uart(fail ? "FAIL 0x" : "PASS 0x");
    print_uart_int(fail);
    print_uart("\n");
    // wait for the uart transmitter to be empty before ending the test
    while (!(*(volatile uint8_t *)(UART_LINE_STATUS) & 0x40)) {}
    return fail ? (0x100 | fail) : 1;
}
