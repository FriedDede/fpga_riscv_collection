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
    else
    {
        while (1) {};
    }
    
    // jump to the start address of the payload 
    __asm__ volatile(
        "li s0, 0x80010000 ;"
        "jalr s0"
    );

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