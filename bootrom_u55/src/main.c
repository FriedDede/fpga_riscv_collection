#include "platform.h"
#include "uart.h"
#include <stdint.h>
#include <stdio.h>

int main()
{   
    init_uart(CORE_CLK,UART_BAUD);

    int *dram_head = (int*) 0x80000000;
    float *dram_head_float = (float*) 0x80000000;
    float j = 0.0f;
    
    // LSU, FPU, muldiv testing for now
    for (int i = 0; i < 256; i++)
    {
        dram_head[i] = i; 
    }
    for (int i = 0; i < 256; i++)
    {
        dram_head[i] = i * dram_head[i]; 
    }
    for (int i = 0; i < 256; i++)
    {
        dram_head[i] = i / dram_head[i]; 
    }
    for (int i = 0; i < 256; i++)
    {
        dram_head_float[i] = (dram_head_float[i] * j); 
        j++;
    }
    j = 0.0f;
    for (int i = 0; i < 256; i++)
    {
        dram_head_float[i] = (dram_head_float[i] / j); 
        j++;
    }

    uint64_t time = *(uint64_t *)(CLINT_BASE + CLINT_TIMER_VAL_OFF);
    // success
    //char time_string[16];
    //sprintf(time_string,"Boot at: %lu ",time);
    
    *(uint64_t*) (dram_head + CLINT_TIMER_VAL_OFF) = time;
 
    print_uart("Hello");

    // jump to the start address of the payload 
    __asm__ volatile(
        "li s0, 0x80010000 ;"
        "jalr s0"
    );

    while (1) {}
}

void handle_trap(void)
{
    while (1) {}
}