/* CVA6 test payload: loaded in DRAM at the bootrom jump address of hart 0 */
OUTPUT_ARCH("riscv")
ENTRY(_start)

SECTIONS
{
    /* checked by tb_cva6 */
    . = 0x80001000;
    .tohost : { tohost = .; LONG(0) }

    . = 0x80010000;
    .text.init : { *(.text.init) }
    .text : { *(.text*) }
    .rodata : { *(.rodata*) *(.srodata*) }
    .data : { *(.data*) *(.sdata*) }
    .bss : ALIGN(8) {
        _bss_start = .;
        *(.bss*) *(.sbss*) *(COMMON)
        . = ALIGN(8);
        _bss_end = .;
    }
}
