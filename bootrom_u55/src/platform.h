// core clock in mhz
#define CORE_CLK 100000000
// dram address space
#define DRAM_BASE 0x80000000
#define DRAM_PAYLOAD_OFFSET 0x10000
#define DRAM_SIZE 0x20000000 //512MB per core
// pheripheral address space
#define DebugBase  0x00000000
#define ROMBase 0x00010000
// clint
#define CLINTBase 0x02000000
#define CLINT_IPI_OFF		0
#define CLINT_TIMER_CMP_OFF	0x4000
#define CLINT_TIMER_VAL_OFF	0xbff8
// clint
#define PLICBase 0x0C000000
#define UARTBase 0x10000000
#define TimerBase 0x18000000
#define SPIBase 0x20000000
#define EthernetBase 0x30000000
#define GPIOBase 0x40000000