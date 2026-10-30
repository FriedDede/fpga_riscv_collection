CROSSCOMPILE ?= riscv64-unknown-elf-
CC 			= ${CROSSCOMPILE}gcc
PYTHON		=python3

# target core: snitch (default), cva, veer, mini
CORE		?= snitch
# outputs (objects, bootrom_<core>.elf/.bin/.img/.dump/.sv), the top Makefile uses build/bootrom
BUILD_DIR	?= $(abspath ../build/bootrom)

LDSCRIPT	= linker.lds
LDLIBS		=

ifeq ($(CORE),veer)
# VeeR-EL2: no fpu, no atomics
 CFLAGS	 = -Os -ggdb -march=rv32imc_zicsr_zifencei -mabi=ilp32 -Wall -DVEER
else ifeq ($(CORE),mini)
# riscv-mini: rv32i only (libgcc for mul/div), reset pc 0x200 and machine mode trap vector 0x1c0
 CFLAGS	 = -Os -ggdb -march=rv32i_zicsr -mabi=ilp32 -Wall -DMINI
 LDSCRIPT	= linker_mini.lds
 LDLIBS		= -lgcc
else ifeq ($(CORE),cva)
# cva6 (ariane)
 CFLAGS 	= -Os -ggdb -march=rv64gc -mabi=lp64d -Wall
else ifeq ($(CORE),snitch)
# snitch
 CFLAGS	 = -Os -ggdb -march=rv32g -mabi=ilp32d -Wall
else
 $(error unknown CORE=$(CORE), expected snitch, cva, veer or mini)
endif

CCASFLAGS 	= -mcmodel=medany -mexplicit-relocs
LDFLAGS 	= -nostdlib -nostartfiles

INCLUDES 	= -I./ -I./src

SRCS_C 		= src/main.c src/uart.c # src/spi.c src/sd.c src/gpt.c
SRCS_ASM 	= startup.S
OBJ_DIR		= $(BUILD_DIR)/obj_$(CORE)
OBJS_C 		= $(addprefix $(OBJ_DIR)/,$(notdir $(SRCS_C:.c=.o)))
OBJS_S 		= $(addprefix $(OBJ_DIR)/,$(notdir $(SRCS_ASM:.S=.o)))

MAIN 		= $(BUILD_DIR)/bootrom_$(CORE).elf
MAIN_BIN 	= $(MAIN:.elf=.bin)
MAIN_IMG 	= $(MAIN:.elf=.img)
MAIN_SV 	= $(MAIN:.elf=.sv)
MAIN_DUMP 	= $(MAIN:.elf=.dump)

.PHONY: all clean
# keep the intermediate images
.SECONDARY: $(MAIN_BIN) $(MAIN_IMG)

all: $(MAIN_SV) $(MAIN_DUMP)
	@echo "zero stage bootloader has been compiled: $(MAIN_SV)"

$(MAIN): $(OBJS_C) $(OBJS_S) $(LDSCRIPT)
	$(CC) $(CFLAGS) $(LDFLAGS) $(INCLUDES) -T$(LDSCRIPT) $(OBJS_S) $(OBJS_C) $(LDLIBS) -o $(MAIN)
	@echo "LD    >= $(MAIN)"

%.img: %.bin
	dd if=$< of=$@ bs=128

%.bin: %.elf
	$(CROSSCOMPILE)objcopy -O binary $< $@

%.dump: %.elf
	$(CROSSCOMPILE)objdump -d $< > $@

$(OBJ_DIR)/%.o: src/%.c
	@mkdir -p $(OBJ_DIR)
	@$(CC) $(CFLAGS) $(INCLUDES) -c $<  -o $@
	@echo "CC    <= $<"

$(OBJ_DIR)/%.o: %.S
	@mkdir -p $(OBJ_DIR)
	@$(CC) $(CFLAGS) $(CCASFLAGS) $(INCLUDES) -c $<  -o $@
	@echo "CC    <= $<"

# module bootrom_<core> (gen_rom.py names it as the file)
%.sv: %.img gen_rom.py
	$(PYTHON) ./gen_rom.py $<
	@echo "PYTHON >= $(MAIN_SV)"

clean:
	$(RM) -r $(OBJ_DIR) $(MAIN) $(MAIN_BIN) $(MAIN_IMG) $(MAIN_SV) $(MAIN_DUMP)

# DO NOT DELETE THIS LINE -- make depend needs it
