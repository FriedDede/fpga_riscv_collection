#include "platform.h"

int main()
{   
    int *dram_head = (int*) 0x80000000;
    float *dram_head_float = (float*) 0x80000000;
    float j = 0.0f;
    
    for (int i = 0; i < 256; i++)
    {
        dram_head[i] = i; 
    }

    for (int i = 0; i < 256; i++)
    {
        dram_head_float[i] = (dram_head_float[i] * j); 
        j++;
    }

    j = 0.0f;
    
    // jump to the address
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