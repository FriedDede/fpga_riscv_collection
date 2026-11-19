// Snitch u55c smoke test: uart, integer mul/div, fpu (through the fp subsystem), DRAM accesses
// from the integer and the fpu lsu ports (code runs from DRAM through the I$).
// Returns 1 on success, 0x100 | failed checks mask otherwise (written to tohost by crt0).
#include <stdint.h>
#include "uart.h"
#include "platform.h"

static uint32_t check_muldiv(void)
{
    volatile int32_t a = -12345, b = 678;
    volatile uint32_t ua = 0xFFFFFFF0u, ub = 7;
    if (a * b != -8369910) return 1;
    if (a / b != -18 || a % b != -141) return 1;
    if (ua / ub != 613566754u || ua % ub != 2) return 1;
    // mulhu
    if ((uint32_t)(((uint64_t)ua * ub) >> 32) != 6) return 1;
    return 0;
}

static uint32_t check_fpu(void)
{
    volatile double a = 1.5, b = 2.25, c = -0.75;
    volatile float  fa = 3.0f, fb = 0.5f;
    double r = a * b + c;                       // fmadd.d
    if (r != 2.625) return 1;
    if ((int)(a * 1000.0) != 1500) return 1;    // fcvt.w.d
    if ((double)(fa * fb + fa) != 4.5) return 1; // single precision, fcvt.d.s
    if (!(c < a) || (a == b)) return 1;         // compares
    return 0;
}

static uint32_t check_dram(void)
{
    static volatile uint32_t data[16];
    static volatile double fdata[16];           // fsd/fld: fpu lsu port
    for (int i = 0; i < 16; i++) data[i] = 0xA5A50000u | i;
    for (int i = 0; i < 16; i++) fdata[i] = 0.5 * i;
    for (int i = 0; i < 16; i++)
        if (data[i] != (0xA5A50000u | i) || fdata[i] != 0.5 * i) return 1;
    // byte and halfword stores
    volatile uint8_t *b = (volatile uint8_t *)data;
    b[1] = 0x11; ((volatile uint16_t *)data)[1] = 0x2233;
    return data[0] == 0x22331100u ? 0 : 1;
}

int main(void)
{
    uint32_t fail = 0;
    init_uart(CORE_CLK, UART_BAUD);
    print_uart("Snitch u55c\n");

    fail |= check_muldiv() << 0;
    fail |= check_fpu()    << 1;
    fail |= check_dram()   << 2;

    print_uart(fail ? "FAIL 0x" : "PASS 0x");
    print_uart_int(fail);
    print_uart("\n");
    // wait for the uart transmitter to be empty before ending the test
    while (!(*(volatile uint8_t *)(UART_LINE_STATUS) & 0x40)) {}
    return fail ? (0x100 | fail) : 1;
}
