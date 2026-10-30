# Copyright 2024 Politecnico di Milano.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
#
# Alveo u55c projects
#   make snitch | cva | veer | mini   create the Vivado project in build/<core> [FREQ_CORE= FREQ_CLUSTER= FREQ_PERIPH=<MHz>, default 50]
#   make bitgen [CORE=<core>]  synthesis + implementation + bitstream (default: last created project)
#   make sim-veer | sim-mini   xcelium simulation of the VeeR / riscv-mini top (sim/<core>)
#
# Every run folder (build/<core>, build/sim-<core>) holds its generated sources:
#   bootrom/       bootrom_<core>.elf/.bin/.img/.dump/.sv (bootrom_u55)
#   veer_snapshot/ VeeR-EL2 configuration (VEER_CONFIG), veer runs
#   riscv_mini/    riscv-mini Tile.sv generated from chisel (sbt), mini runs

VIVADO      ?= vivado
PYTHON      ?= python3
JOBS        ?= 8
BUILD_DIR   ?= $(CURDIR)/build
# clocks in MHz: cores, cluster crossbars (and hbm channels), peripherals
FREQ_CORE    ?= 50
FREQ_CLUSTER ?= 50
FREQ_PERIPH  ?= 50

CORE        ?= $(shell cat $(BUILD_DIR)/.core 2>/dev/null)

VIVADO_BATCH = $(VIVADO) -mode batch -nojournal -notrace

# VeeR-EL2 configuration, see hw/cores/Cores-VeeR-EL2/configs/veer.config
VEER_ROOT     = $(CURDIR)/hw/cores/Cores-VeeR-EL2
VEER_CONFIG   = -target=default -set=reset_vec=0x0 -set=nmi_vec=0x0 -set=iccm_enable=0 -set=icache_waypack=0 -set=dma_bus_tag=8 -fpga_optimize=1
MINI_ROOT     = $(CURDIR)/hw/cores/riscv-mini
MINI_SRCS     = $(wildcard $(MINI_ROOT)/src/main/scala/*/*.scala)
BOOTROM_SRCS  = $(wildcard bootrom_u55/*.S bootrom_u55/*.lds bootrom_u55/src/*.c bootrom_u55/src/*.h) bootrom_u55/Makefile bootrom_u55/gen_rom.py

# per core: bootrom (bootrom_u55 CORE=) and generated sources of the run
BOOTROM_snitch = snitch
BOOTROM_cva6   = cva
BOOTROM_veer   = veer
BOOTROM_mini   = mini
GEN_veer       = veer_snapshot/common_defines.vh
GEN_mini       = riscv_mini/Tile.sv

.PHONY: all snitch cva veer mini bitgen sim-veer sim-mini clean
# the generated sources are built by pattern rules: never delete them as intermediate files
.SECONDARY:

all:
	@echo "usage: make snitch | cva | veer | mini | bitgen [CORE=snitch|cva6|veer|mini] | sim-veer | sim-mini | clean"

# -----------------
# Vivado projects
# -----------------
snitch: project-snitch
cva:    project-cva6
veer:   project-veer
mini:   project-mini

.SECONDEXPANSION:
project-%: $$(BUILD_DIR)/$$*/bootrom/bootrom_$$(BOOTROM_$$*).sv $$(addprefix $$(BUILD_DIR)/$$*/,$$(GEN_$$*))
	$(PYTHON) -I tcl_scripts/filelists/gen_filelist.py $* --bootrom $< \
		--veer-snapshot $(BUILD_DIR)/$*/veer_snapshot --mini-rtl $(BUILD_DIR)/$*/riscv_mini/Tile.sv > $(BUILD_DIR)/$*/$*.f
	cd $(BUILD_DIR)/$* && $(VIVADO_BATCH) -log create_project.log \
		-source $(CURDIR)/tcl_scripts/create_project.tcl -tclargs $* $(BUILD_DIR)/$* $(BUILD_DIR)/$*/$*.f $(FREQ_CORE) $(FREQ_CLUSTER) $(FREQ_PERIPH)
	echo $* > $(BUILD_DIR)/.core

bitgen:
	@test -n "$(CORE)" || (echo "no project: run make snitch | cva | veer | mini first" && exit 1)
	@test -f $(BUILD_DIR)/$(CORE)/u55_$(CORE).xpr || (echo "missing $(BUILD_DIR)/$(CORE)/u55_$(CORE).xpr, run make first" && exit 1)
	cd $(BUILD_DIR)/$(CORE) && $(VIVADO_BATCH) -log run_impl.log \
		-source $(CURDIR)/tcl_scripts/run_impl.tcl -tclargs $(BUILD_DIR)/$(CORE)/u55_$(CORE).xpr $(JOBS)

# -----------------
# Generated sources of a run: build/<run>/...
# -----------------
# bootrom_u55, one rule per bootrom core
define BOOTROM_RULE
$$(BUILD_DIR)/%/bootrom/bootrom_$(1).sv: $$(BOOTROM_SRCS)
	$$(MAKE) -C bootrom_u55 CORE=$(1) BUILD_DIR=$$(dir $$@) all
endef
$(foreach c,snitch cva veer mini,$(eval $(call BOOTROM_RULE,$(c))))

# VeeR-EL2 snapshot (VEER_CONFIG is in this Makefile)
$(BUILD_DIR)/%/veer_snapshot/common_defines.vh: Makefile
	rm -rf $(dir $@) && mkdir -p $(dir $@)
	cd $(VEER_ROOT) && RV_ROOT=$(VEER_ROOT) BUILD_PATH=$(dir $@) perl configs/veer.config $(VEER_CONFIG) > $(dir $@)/veer.config.log

# riscv-mini: chisel -> systemverilog with sbt (hw/cores/riscv-mini/Makefile), sbt caches stay in the submodule
$(BUILD_DIR)/%/riscv_mini/Tile.sv: $(MINI_SRCS)
	mkdir -p $(dir $@)
	$(MAKE) -C $(MINI_ROOT) compile gen_dir=$(dir $@) > $(dir $@)/sbt.log 2>&1 || (tail -20 $(dir $@)/sbt.log; exit 1)

# -----------------
# Simulations
# -----------------
sim-veer: $(BUILD_DIR)/sim-veer/bootrom/bootrom_veer.sv $(BUILD_DIR)/sim-veer/veer_snapshot/common_defines.vh
	$(MAKE) -C sim/veer BUILD_DIR=$(BUILD_DIR)/sim-veer BOOTROM=$< VEER_SNAPSHOT=$(BUILD_DIR)/sim-veer/veer_snapshot

sim-mini: $(BUILD_DIR)/sim-mini/bootrom/bootrom_mini.sv $(BUILD_DIR)/sim-mini/riscv_mini/Tile.sv
	$(MAKE) -C sim/mini BUILD_DIR=$(BUILD_DIR)/sim-mini BOOTROM=$< MINI_RTL=$(BUILD_DIR)/sim-mini/riscv_mini/Tile.sv

clean:
	rm -rf $(BUILD_DIR)
