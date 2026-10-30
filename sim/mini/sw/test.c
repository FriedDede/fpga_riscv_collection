// riscv-mini u55c smoke test: stack and data in DRAM through the write-back D$, D$ evictions
// and refills through the cluster crossbar and the HBM, libgcc mul/div (rv32i).
// Returns 1 on success, 0x100 | failed checks mask otherwise (written to mtohost by crt0).
#include <stdint.h>

// twice the 4KB direct mapped D$: the first half is written back to the HBM by the second
#define ARRAY_WORDS 2048
static volatile uint32_t array[ARRAY_WORDS];

static uint32_t fact(uint32_t n)
{
    return n <= 1 ? 1 : n * fact(n - 1);
}

static uint32_t check_stack(void)
{
    return fact(10) == 3628800u ? 0 : 1;
}

static uint32_t check_muldiv(void)
{
    volatile uint32_t a = 1000003u, b = 97u;
    return (a * b == 97000291u && a / b == 10309u && a % b == 30u) ? 0 : 1;
}

static uint32_t check_dram(void)
{
    for (uint32_t i = 0; i < ARRAY_WORDS; i++) array[i] = 0x5A000000u ^ (i * 2654435761u);
    for (uint32_t i = 0; i < ARRAY_WORDS; i++)
        if (array[i] != (0x5A000000u ^ (i * 2654435761u))) return 1;
    return 0;
}

int main(void)
{
    uint32_t fail = 0;
    fail |= check_stack()  << 0;
    fail |= check_muldiv() << 1;
    fail |= check_dram()   << 2;
    return fail ? (0x100 | fail) : 1;
}
