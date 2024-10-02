#include "uart.h"
#include "platform.h"
#include <stdint.h>
#include <stdio.h>

int main()
{
    uint32_t hartid;
    asm volatile ("csrr %0, mhartid" : "=r"(hartid));
    if (hartid == 0)
    {
        init_uart(CORE_CLK,UART_BAUD);
    }

    // jump to the start address of the payload 
    switch (hartid)
    {
    case 0:  
        __asm__ volatile(
            "li s0, 0x80010000 ;"
            "jalr s0"
        );
        break;
    case 1:
        __asm__ volatile(
            "li s0, 0x82010000 ;"
            "jalr s0"
        );
        break;
    case 2:
        __asm__ volatile(
            "li s0, 0x84010000 ;"
            "jalr s0"
        );
        break;
    case 3:
        __asm__ volatile(
            "li s0, 0x86010000 ;"
            "jalr s0"
        );
        break;
    case 4:  
        __asm__ volatile(
            "li s0, 0x88010000 ;"
            "jalr s0"
        );
        break;
    case 5:
        __asm__ volatile(
            "li s0, 0x8A010000 ;"
            "jalr s0"
        );
        break;
    case 6:
        __asm__ volatile(
            "li s0, 0x8C010000 ;"
            "jalr s0"
        );
        break;
    case 7:
        __asm__ volatile(
            "li s0, 0x8E010000 ;"
            "jalr s0"
        );
        break;
    default:
        break;
    }

    if (hartid == 0)
    {
        print_uart("Success\n");
    }
    return 0;
}

void handle_trap(void)
{
    while (1) {}
}