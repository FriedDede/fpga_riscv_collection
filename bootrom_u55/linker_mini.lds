/* riscv-mini: machine mode trap vector at 0x1c0 (mtvec 0x100 + 0x40 * prv), reset pc 0x200 (startup.S, CORE=mini) */
ENTRY(main)

SECTIONS
{
    ROM_BASE = 0x00000; /* ... but actually position independent */

    . = ROM_BASE;
    /* the rom image starts at 0: objcopy -O binary starts at the first section */
    .rom_base : { LONG(0) }

    /* riscv-mini fixed machine mode trap vector and reset pc */
    . = 0x1c0;
    .text.trap : { *(.text.trap) }
    . = 0x200;
    .text.init : { *(.text.init) }

    .text : ALIGN(0x100) {
    _TEXT_START_ = .;
        *(.text)
    _TEXT_END_ = .;
    }

    .data : ALIGN(0x100) {
    _DATA_START_ = .;
        *(.data)
    _DATA_END_ = .;
    }

    PROVIDE(_data = ADDR(.data));
    PROVIDE(_data_lma = LOADADDR(.data));
    PROVIDE(_edata = .);

    .bss : ALIGN(0x100) {
    _BSS_START_ = .;
        *(.bss)
    _BSS_END_ = .;
    }

    .rodata : ALIGN(0x100) {
    _RODATA_START_ = .;
        *(.rodata)
        *(.dtb*)
        *(.rodata*)
    _RODATA_END_ = .;
    }
}
