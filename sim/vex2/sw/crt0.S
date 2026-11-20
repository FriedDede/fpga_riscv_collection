# VexiiRiscv test payload entry, jumped to by bootrom_vex at 0x80010000.
# The bootrom already set mtvec and the stack pointer (dram end).
  .section .text.init
  .globl _start
_start:
// clear bss
  la      t0, _bss_start
  la      t1, _bss_end
1:
  bgeu    t0, t1, 2f
  sw      zero, 0(t0)
  addi    t0, t0, 4
  j       1b
2:
  call    main
// report the result to the testbench: the D$ is write-back, flush the tohost line to the DRAM
  la      t0, tohost
  sw      a0, 0(t0)
  cbo.flush 0(t0)
  fence
3:
  j       3b
