# start sequence of the bootloader
#
#
#include <smp.h>
#define DRAM_BASE 0x80000000
#define DRAM_SIZE 0x20000000
  .section .text.init
  .option norvc
  .globl _prog_start
_prog_start:
  smp_pause(s1, s2)
  la      t0, handle_trap
  csrrw   zero, mtvec, t0
  li sp, DRAM_BASE + DRAM_SIZE
  call main
  smp_resume(s1, s2)
  csrr a0, mhartid
//  la a1, _dtb
  li s1, DRAM_BASE
  jr s1

//  .section .dtb
//  .globl _dtb
//  .align 4, 0
//_dtb:
//  .incbin "ariane.dtb"