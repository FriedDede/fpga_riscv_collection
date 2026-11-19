# Copyright 2024 Politecnico di Milano.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
#
# xcelium simulation of hw/cluster/tops/u55_cva6_top.sv with the sw/test.c payload
#   make            build the payload, compile and run
#   make GUI=1      same, with simvision

REPO        := $(abspath ../..)
BUILD_DIR   ?= $(REPO)/build/sim-cva6
BOOTROM     ?= $(REPO)/build/sim-cva6/bootrom/bootrom_cva.sv
CROSSCOMPILE ?= riscv64-unknown-elf-
PYTHON      ?= python3
XRUN        ?= xrun
VIVADO_ROOT ?= $(abspath $(dir $(shell which vivado))/..)
GUI         ?= 0

SW_CFLAGS   = -Os -g -march=rv64gc_zicsr_zifencei -mabi=lp64d -mcmodel=medany -Wall -nostdlib -nostartfiles \
              -I$(REPO)/bootrom_u55/src
SW_SRCS     = sw/crt0.S sw/test.c $(REPO)/bootrom_u55/src/uart.c

XRUN_FLAGS  = -64bit -sv -v93 -timescale 1ns/1ps -access +rwc -licqueue \
              -xmlibdirpath $(BUILD_DIR) \
              -y $(VIVADO_ROOT)/data/verilog/src/unisims +libext+.v \
              -top tb_cva6 -top glbl
ifeq ($(GUI),1)
XRUN_FLAGS += -gui
endif

.PHONY: run clean

run: $(BUILD_DIR)/test.hex $(BUILD_DIR)/cva6.f
	cd $(BUILD_DIR) && $(XRUN) $(XRUN_FLAGS) -l xrun.log \
		-f $(BUILD_DIR)/cva6.f \
		$(abspath ../models/hbm_interface_sim.sv ../models/xlnx_clk_gen_sim.sv tb_cva6.sv) \
		$(VIVADO_ROOT)/data/verilog/src/glbl.v \
		+DRAM_HEX=$(BUILD_DIR)/test.hex
	@grep -q "\[tb_cva6\] tohost.*PASS" $(BUILD_DIR)/xrun.log

# rtl sources with absolute paths
$(BUILD_DIR)/cva6.f: $(REPO)/tcl_scripts/filelists/gen_filelist.py $(BOOTROM)
	mkdir -p $(BUILD_DIR)
	$(PYTHON) -I $(word 1,$^) cva6 --bootrom $(BOOTROM) | sed -e 's#^+incdir+\([^/]\)#+incdir+$(REPO)/\1#' -e '/^[^+/]/s#^#$(REPO)/#' > $@

$(BUILD_DIR)/test.elf: $(SW_SRCS) sw/link.ld
	mkdir -p $(BUILD_DIR)
	$(CROSSCOMPILE)gcc $(SW_CFLAGS) -Tsw/link.ld $(SW_SRCS) -lgcc -o $@
	$(CROSSCOMPILE)objdump -d $@ > $(BUILD_DIR)/test.dump

# DRAM 0x8000_0000 is HBM address 0x0
$(BUILD_DIR)/test.hex: $(BUILD_DIR)/test.elf
	$(CROSSCOMPILE)objcopy -O verilog --change-addresses=-0x80000000 $< $@

clean:
	rm -rf $(BUILD_DIR)
