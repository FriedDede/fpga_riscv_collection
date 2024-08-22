#include "platform.h"

int main()
{   

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