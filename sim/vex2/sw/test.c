// VexiiRiscv u55c smoke test: uart, mul/div, DRAM accesses through the write-back D$ (evictions,
// cbo.flush / cbo.inval), I$/D$ hits, ecall and the CLINT timer and software interrupts (own trap
// handler in mtvec).
// Returns 1 on success, 0x100 | failed checks mask otherwise (written to tohost by crt0).
#include <stdint.h>
#include "uart.h"
#include "platform.h"

#define CLINT_MSIP      (CLINT_BASE + CLINT_IPI_OFF)
#define CLINT_MTIMECMP  (CLINT_BASE + CLINT_TIMER_CMP_OFF)
#define CLINT_MTIME     (CLINT_BASE + CLINT_TIMER_VAL_OFF)
#define MIP_MSIP        (1u << 3)
#define MIP_MTIP        (1u << 7)

#define REG32(addr) (*(volatile uint32_t *)(addr))

static volatile uint32_t ecalls, timer_irqs, soft_irqs, bad_traps, timer_irq_mtime;

__attribute__((interrupt("machine"), aligned(4))) static void trap_handler(void)
{
    uint32_t mcause, mepc;
    asm volatile ("csrr %0, mcause" : "=r"(mcause));
    if (mcause == 0x80000007u) {            // machine timer: mask it
        asm volatile ("csrc mie, %0" :: "r"(MIP_MTIP));
        timer_irq_mtime = REG32(CLINT_MTIME);
        timer_irqs++;
    } else if (mcause == 0x80000003u) {     // machine software: clear msip
        REG32(CLINT_MSIP) = 0;
        soft_irqs++;
    } else {
        if (mcause == 11) ecalls++;         // ecall from M mode
        else bad_traps++;
        asm volatile ("csrr %0, mepc" : "=r"(mepc));
        asm volatile ("csrw mepc, %0" :: "r"(mepc + 4));
    }
}

static uint32_t check_muldiv(void)
{
    volatile int32_t a = -12345, b = 678;
    volatile uint32_t ua = 0xFFFFFFF0u, ub = 7;
    if (a * b != -8369910) return 1;
    if (a / b != -18 || a % b != -141) return 1;
    if (ua / ub != 613566754u || ua % ub != 2) return 1;
    // mulhu, mulh
    if ((uint32_t)(((uint64_t)ua * ub) >> 32) != 6) return 1;
    if ((int32_t)(((int64_t)a * -b) >> 32) != 0) return 1;
    return 0;
}

static uint32_t check_dram(void)
{
    static volatile uint32_t data[64] __attribute__((aligned(64)));
    for (int i = 0; i < 64; i++) data[i] = 0xA5A50000u | i;
    for (int i = 0; i < 64; i++)
        if (data[i] != (0xA5A50000u | i)) return 1;
    // byte and halfword stores
    volatile uint8_t *b = (volatile uint8_t *)data;
    b[1] = 0x11; ((volatile uint16_t *)data)[1] = 0x2233;
    if (data[0] != 0x22331100u) return 1;
    // the D$ is write-back: the dirty lines of data[] are written back when evicted (8 KiB direct
    // mapped, every set is touched) and refilled from the DRAM
    static volatile uint32_t evict[2048];
    for (int i = 0; i < 2048; i++) (void)evict[i];
    if (data[0] != 0x22331100u || data[63] != (0xA5A50000u | 63)) return 1;
    // cbo.flush writes the line back, cbo.inval drops the (dirty) cached copy: the load after it
    // reads the flushed value from the DRAM
    data[16] = 0x600DF00Du;
    asm volatile ("cbo.flush 0(%0)" :: "r"(&data[16]) : "memory");
    data[16] = 0xBAADF00Du;
    asm volatile ("cbo.inval 0(%0)" :: "r"(&data[16]) : "memory");
    return data[16] == 0x600DF00Du ? 0 : 1;
}

// the same loop (code and data) runs twice: the second run hits in the I$, D$ and branch predictor
__attribute__((noinline)) static uint32_t timed_loop(volatile uint32_t *acc)
{
    uint32_t c0, c1;
    asm volatile ("csrr %0, mcycle" : "=r"(c0));
    for (int i = 0; i < 64; i++) *acc += i;
    asm volatile ("csrr %0, mcycle" : "=r"(c1));
    return c1 - c0;
}

static uint32_t check_caches(void)
{
    static volatile uint32_t acc;
    uint32_t cold, warm;
    acc = 0;
    asm volatile ("fence.i" ::: "memory");      // cold I$
    cold = timed_loop(&acc);
    warm = timed_loop(&acc);
    print_uart("loop cycles 0x");
    print_uart_int(cold);
    print_uart(" 0x");
    print_uart_int(warm);
    print_uart("\n");
    return (acc == 2 * 2016 && warm < cold) ? 0 : 1;
}

static uint32_t check_traps(void)
{
    uint32_t old_mtvec, hartid;
    asm volatile ("csrr %0, mhartid" : "=r"(hartid));
    asm volatile ("csrrw %0, mtvec, %1" : "=r"(old_mtvec) : "r"(trap_handler));

    // ecall
    asm volatile ("ecall" ::: "memory");

    // software interrupt: msip of this hart in the CLINT
    asm volatile ("csrs mie, %0" :: "r"(MIP_MSIP));
    asm volatile ("csrs mstatus, 8");
    REG32(CLINT_MSIP + 4 * hartid) = 1;
    for (int i = 0; i < 1000 && !soft_irqs; i++) {}

    // timer interrupt, mtimecmp a few rtc ticks from now (32 bit halves: the CLINT must honour the
    // byte enables). mtip is pending since reset (mtimecmp = 0): read mtimecmp back (the read waits
    // for the posted writes) and let mtip clear through the core synchronizers before enabling it
    uint32_t now = REG32(CLINT_MTIME);
    uint32_t cmp = now + 200;
    REG32(CLINT_MTIMECMP + 8 * hartid + 4) = 0;
    REG32(CLINT_MTIMECMP + 8 * hartid)     = cmp;
    if (REG32(CLINT_MTIMECMP + 8 * hartid) != cmp || REG32(CLINT_MTIMECMP + 8 * hartid + 4) != 0) bad_traps++;
    for (volatile int i = 0; i < 4; i++) {}
    asm volatile ("csrs mie, %0" :: "r"(MIP_MTIP));
    for (int i = 0; i < 100000 && !timer_irqs; i++) {}

    asm volatile ("csrc mstatus, 8");
    asm volatile ("csrw mtvec, %0" :: "r"(old_mtvec));
    print_uart("hart 0x");
    print_uart_int(hartid);
    print_uart(" ecall 0x");
    print_uart_int(ecalls);
    print_uart(" msi 0x");
    print_uart_int(soft_irqs);
    print_uart(" mti 0x");
    print_uart_int(timer_irqs);
    print_uart(" at mtime 0x");
    print_uart_int(timer_irq_mtime);
    print_uart(" (mtimecmp 0x");
    print_uart_int(cmp);
    print_uart(")\n");
    return (hartid == 0 && ecalls == 1 && soft_irqs == 1 && timer_irqs == 1 && bad_traps == 0 &&
            timer_irq_mtime >= cmp) ? 0 : 1;
}

int main(void)
{
    uint32_t fail = 0;
    init_uart(CORE_CLK, UART_BAUD);
    print_uart("VexiiRiscv u55c\n");

    fail |= check_muldiv() << 0;
    fail |= check_dram()   << 1;
    fail |= check_caches() << 2;
    fail |= check_traps()  << 3;

    print_uart(fail ? "FAIL 0x" : "PASS 0x");
    print_uart_int(fail);
    print_uart("\n");
    // wait for the uart transmitter to be empty before ending the test
    while (!(*(volatile uint8_t *)(UART_LINE_STATUS) & 0x40)) {}
    return fail ? (0x100 | fail) : 1;
}
