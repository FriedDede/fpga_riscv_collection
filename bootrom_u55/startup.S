# start sequence of the bootloader
#
#
#include <smp.h>
#define DRAM_BASE 0x80000000
#define DRAM_SIZE 0x10000000
// VeeR-EL2, must match the snapshot (VEER_CONFIG in the Makefile)
#define VEER_MRAC       0x0001000A
#define VEER_DCCM_BASE  0xF0040000
#define VEER_DCCM_SIZE  0x00010000
  .section .text.init
  .option norvc
  .globl _prog_start
_prog_start:
#ifndef MINI
// initalize trap handler (riscv-mini: mtvec is read only, the vector is .text.trap at 0x1c0)
  la      t0, handle_trap
  csrrw   zero, mtvec, t0
#endif
#ifdef VEER
// VeeR region access control (mrac): {side_effect, cacheable} per 256MB region
// region 0x0 (rom, clint) and 0x1 (uart, timer) side effect, region 0x8 (dram) cacheable
  li t0, VEER_MRAC
  csrw 0x7c0, t0
// initliaze stack pointer at dccm end (VeeR has no fpu)
  li sp, VEER_DCCM_BASE + VEER_DCCM_SIZE
#elif defined(MINI)
// riscv-mini: rv32i, no fpu, stack at dram end (through the write-back D$)
  li sp, DRAM_BASE + DRAM_SIZE
#else
// initialize fpu
  li t0, 1 << 13
  csrw mstatus, t0
// initliaze stack pointer at dram end
  li sp, DRAM_BASE + DRAM_SIZE
#endif
  call main

_end:
  j _end

#ifdef MINI
// riscv-mini fixed machine mode trap vector (mtvec 0x100 + 0x40 * prv = 0x1c0, linker_mini.lds)
  .section .text.trap
  .globl _trap_vector
_trap_vector:
  j handle_trap
#endif
