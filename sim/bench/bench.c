// Core IPC benchmark, the same source for every rv32im core of the u55c tops (sim/<core>,
// make sim-<core> TEST=../bench/bench.c). Each kernel runs once to warm the caches and branch
// predictors, then again measured with mcycle / minstret (core clock). The stream kernels work on
// 32 KiB, larger than the D$ of the cores: they measure the refill (and writeback) path.
// Output lines (uart, hex):  BENCH <name> <cycles> <instret> <checksum>
// Returns 1 (tohost): compare the checksums between cores (same compiler flags, same data).
#include <stdint.h>
#include "uart.h"
#include "platform.h"

static inline uint32_t rdcycle(void)   { uint32_t v; asm volatile ("csrr %0, mcycle"   : "=r"(v)); return v; }
static inline uint32_t rdinstret(void) { uint32_t v; asm volatile ("csrr %0, minstret" : "=r"(v)); return v; }

static uint32_t lcg_state;
static uint32_t lcg(void) { lcg_state = lcg_state * 1664525u + 1013904223u; return lcg_state; }

// -----------------
// kernels
// -----------------
#define CRC_LEN   1024
#define COPY_WORDS 1024          // 4 KiB
#define MAT_N     16
#define SORT_N    128
#define CHASE_N   256
#define STREAM_WORDS 8192        // 32 KiB
#define DIV_N     256

static uint8_t  crc_buf[CRC_LEN];
static uint32_t copy_src[COPY_WORDS], copy_dst[COPY_WORDS];
static int32_t  mat_a[MAT_N][MAT_N], mat_b[MAT_N][MAT_N], mat_c[MAT_N][MAT_N];
static int32_t  sort_src[SORT_N], sort_buf[SORT_N];
static uint32_t chase_next[CHASE_N];
static uint32_t stream_buf[STREAM_WORDS];

// bitwise crc32: alu, data dependent branches
__attribute__((noinline)) static uint32_t k_crc32(void)
{
    uint32_t crc = 0xFFFFFFFFu;
    for (int i = 0; i < CRC_LEN; i++) {
        crc ^= crc_buf[i];
        for (int b = 0; b < 8; b++)
            crc = (crc & 1) ? (crc >> 1) ^ 0xEDB88320u : crc >> 1;
    }
    return ~crc;
}

// word copy, 4 KiB: load / store throughput on D$ hits
__attribute__((noinline)) static uint32_t k_copy(void)
{
    for (int i = 0; i < COPY_WORDS; i += 4) {
        copy_dst[i]     = copy_src[i];
        copy_dst[i + 1] = copy_src[i + 1];
        copy_dst[i + 2] = copy_src[i + 2];
        copy_dst[i + 3] = copy_src[i + 3];
    }
    return copy_dst[7] ^ copy_dst[COPY_WORDS - 1];
}

// 16x16 integer matrix multiply: mul, load-use
__attribute__((noinline)) static uint32_t k_matmul(void)
{
    uint32_t sum = 0;
    for (int i = 0; i < MAT_N; i++)
        for (int j = 0; j < MAT_N; j++) {
            int32_t acc = 0;
            for (int k = 0; k < MAT_N; k++) acc += mat_a[i][k] * mat_b[k][j];
            mat_c[i][j] = acc;
            sum += acc;
        }
    return sum;
}

// insertion sort of 128 random values: unpredictable branches, load / store
__attribute__((noinline)) static uint32_t k_sort(void)
{
    for (int i = 0; i < SORT_N; i++) sort_buf[i] = sort_src[i];
    for (int i = 1; i < SORT_N; i++) {
        int32_t v = sort_buf[i];
        int j = i - 1;
        while (j >= 0 && sort_buf[j] > v) { sort_buf[j + 1] = sort_buf[j]; j--; }
        sort_buf[j + 1] = v;
    }
    return sort_buf[0] ^ sort_buf[SORT_N / 2] ^ sort_buf[SORT_N - 1];
}

// pointer chasing over a random cycle: load-to-use latency
__attribute__((noinline)) static uint32_t k_chase(void)
{
    uint32_t p = 0;
    for (int i = 0; i < 4 * CHASE_N; i++) p = chase_next[p];
    return p;
}

// recursive fibonacci: calls and returns
__attribute__((noinline)) static uint32_t fib(uint32_t n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }
__attribute__((noinline)) static uint32_t k_fib(void) { return fib(15); }

// divisions
__attribute__((noinline)) static uint32_t k_div(void)
{
    uint32_t acc = 0, x = 0x9E3779B9u;
    for (uint32_t i = 1; i <= DIV_N; i++) {
        acc += x / i + x % (i + 3);
        x ^= acc;
    }
    return acc;
}

// 32 KiB read stream (larger than the D$): refills
__attribute__((noinline)) static uint32_t k_stream_rd(void)
{
    uint32_t sum = 0;
    for (int i = 0; i < STREAM_WORDS; i += 4)
        sum += stream_buf[i] + stream_buf[i + 1] + stream_buf[i + 2] + stream_buf[i + 3];
    return sum;
}

// 32 KiB read-modify-write stream: refills and (write-back D$) writebacks
__attribute__((noinline)) static uint32_t k_stream_rw(void)
{
    for (int i = 0; i < STREAM_WORDS; i++) stream_buf[i] += i;
    return stream_buf[1] ^ stream_buf[STREAM_WORDS - 1];
}

// -----------------
// harness
// -----------------
typedef struct { const char *name; uint32_t (*fn)(void); } kernel_t;

static const kernel_t kernels[] = {
    {"crc32    ", k_crc32},
    {"copy     ", k_copy},
    {"matmul   ", k_matmul},
    {"sort     ", k_sort},
    {"chase    ", k_chase},
    {"fib      ", k_fib},
    {"div      ", k_div},
    {"stream_rd", k_stream_rd},
    {"stream_rw", k_stream_rw},
};
#define NUM_KERNELS (sizeof(kernels) / sizeof(kernels[0]))

static void init_data(void)
{
    lcg_state = 12345;
    for (int i = 0; i < CRC_LEN; i++) crc_buf[i] = lcg() >> 24;
    for (int i = 0; i < COPY_WORDS; i++) copy_src[i] = lcg();
    for (int i = 0; i < MAT_N; i++)
        for (int j = 0; j < MAT_N; j++) { mat_a[i][j] = (int32_t)(lcg() >> 20) - 2048; mat_b[i][j] = (int32_t)(lcg() >> 20) - 2048; }
    for (int i = 0; i < SORT_N; i++) sort_src[i] = (int32_t)lcg();
    // random single cycle (Sattolo)
    for (uint32_t i = 0; i < CHASE_N; i++) chase_next[i] = i;
    for (uint32_t i = CHASE_N - 1; i > 0; i--) {
        uint32_t j = lcg() % i, t = chase_next[i];
        chase_next[i] = chase_next[j]; chase_next[j] = t;
    }
    for (int i = 0; i < STREAM_WORDS; i++) stream_buf[i] = i * 3;
}

int main(void)
{
    uint32_t total_cycles = 0, total_instret = 0, checks[NUM_KERNELS];
    init_uart(CORE_CLK, UART_BAUD);
    init_data();
    for (unsigned k = 0; k < NUM_KERNELS; k++) {
        kernels[k].fn();                        // warm up
        uint32_t c0 = rdcycle(), i0 = rdinstret();
        checks[k] = kernels[k].fn();
        uint32_t c1 = rdcycle(), i1 = rdinstret();
        print_uart("BENCH ");
        print_uart(kernels[k].name);
        print_uart(" ");
        print_uart_int(c1 - c0);
        print_uart(" ");
        print_uart_int(i1 - i0);
        print_uart(" ");
        print_uart_int(checks[k]);
        print_uart("\n");
        total_cycles += c1 - c0;
        total_instret += i1 - i0;
    }
    print_uart("BENCH total     ");
    print_uart_int(total_cycles);
    print_uart(" ");
    print_uart_int(total_instret);
    print_uart("\n");
    while (!(*(volatile uint8_t *)(UART_LINE_STATUS) & 0x40)) {}
    return 1;
}
