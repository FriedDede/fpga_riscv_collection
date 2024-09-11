#include "uart.h"
#include "platform.h"
#include <stdint.h>
#include <stdio.h>

int bench_wrap()
{
    uint64_t star_time = *(uint64_t *)(CLINT_BASE + CLINT_TIMER_VAL_OFF);

    // jump to the start address of the payload 
    __asm__ volatile(
        "li s0, 0x80010000 ;"
        "jalr s0"
    );

    uint64_t end_time = *(uint64_t *)(CLINT_BASE + CLINT_TIMER_VAL_OFF);
    uint64_t time = end_time - star_time;
    print_uart("Exec CLINT time: \n");
    print_uart_int((uint32_t*)time);
    return 0;
}
