# Copyright 2024 Politecnico di Milano.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
#
# Alveo u55c projects
#   make snitch | cva | veer | mini | vex | vex2   create the Vivado project in build/<core> [FREQ_CORE= FREQ_CLUSTER= FREQ_PERIPH=<MHz>, default 50]
#   make bitgen [CORE=<core>]  synthesis + implementation + bitstream (default: last created project)
#               [SYNTH_STRATEGY=<name>] [IMPL_STRATEGY=<name>]  Vivado strategies (default: Vivado defaults)
#   make sim-snitch | sim-cva6 | sim-veer | sim-mini | sim-vex | sim-vex2   xcelium simulation of a top (sim/<core>)
#
# Every run folder (build/<core>, build/sim-<core>) holds its generated sources:
#   bootrom/       bootrom_<core>.elf/.bin/.img/.dump/.sv (bootrom_u55)
#   veer_snapshot/ VeeR-EL2 configuration (VEER_CONFIG), veer runs
#   riscv_mini/    riscv-mini Tile.sv generated from chisel (sbt), mini runs
#   vexriscv/      VexRiscvU55.v generated from SpinalHDL (sbt), vex runs
#   vexiiriscv/    VexiiRiscvU55.v generated from SpinalHDL (sbt), vex2 runs
# The Vivado IP cache (IP_CACHE, default build/ip_cache) is shared by all the projects, also the
# ones in another BUILD_DIR: the IPs whose configuration does not change (qdma, hbm, ...) are
# synthesized once. Delete it to force their regeneration

VIVADO      ?= vivado
PYTHON      ?= python3
JOBS        ?= 8
BUILD_DIR   ?= $(CURDIR)/build
IP_CACHE    ?= $(CURDIR)/build/ip_cache
# clocks in MHz: cores, cluster crossbars (and hbm channels), peripherals
FREQ_CORE    ?= 50
FREQ_CLUSTER ?= 50
FREQ_PERIPH  ?= 50
# Vivado run strategies for make bitgen, e.g. Flow_PerfOptimized_high / Performance_Explore
SYNTH_STRATEGY ?=
IMPL_STRATEGY  ?=

CORE        ?= $(shell cat $(BUILD_DIR)/.core 2>/dev/null)

VIVADO_BATCH = $(VIVADO) -mode batch -nojournal -notrace

# VeeR-EL2 configuration, see hw/cores/veer/Cores-VeeR-EL2/configs/veer.config
VEER_ROOT     = $(CURDIR)/hw/cores/veer/Cores-VeeR-EL2
VEER_CONFIG   = -target=default -set=reset_vec=0x0 -set=nmi_vec=0x0 -set=iccm_enable=0 -set=icache_waypack=0 -set=dma_bus_tag=8 -fpga_optimize=1
MINI_ROOT     = $(CURDIR)/hw/cores/riscv-mini
MINI_SRCS     = $(wildcard $(MINI_ROOT)/src/main/scala/*/*.scala)
# VexRiscv: GenFullNoMmuMaxPerf configuration with AXI4 buses, see hw/cores/vex/GenVexRiscvU55.scala
VEX_ROOT      = $(CURDIR)/hw/cores/vex/VexRiscv
VEX_GEN       = $(CURDIR)/hw/cores/vex/GenVexRiscvU55.scala
VEX_SRCS      = $(VEX_GEN) $(shell find $(VEX_ROOT)/src/main/scala -name '*.scala' 2>/dev/null)
# VexiiRiscv: RV32IM with I$/D$ and AXI4 buses, see hw/cores/vex2/GenVexiiRiscvU55.scala
VEX2_ROOT     = $(CURDIR)/hw/cores/vex2/VexiiRiscv
VEX2_GEN      = $(CURDIR)/hw/cores/vex2/GenVexiiRiscvU55.scala
VEX2_SRCS     = $(VEX2_GEN) $(shell find $(VEX2_ROOT)/src/main/scala -name '*.scala' 2>/dev/null)
# extra VexiiRiscv options over the u55 configuration, e.g. VEX2_ARGS="--decoders 2 --lanes 2".
# The generated core is not rebuilt when they change: use another BUILD_DIR per variant
VEX2_ARGS    ?=
BOOTROM_SRCS  = $(wildcard bootrom_u55/*.S bootrom_u55/*.lds bootrom_u55/src/*.c bootrom_u55/src/*.h) bootrom_u55/Makefile bootrom_u55/gen_rom.py

# per core: bootrom (bootrom_u55 CORE=) and generated sources of the run
BOOTROM_snitch = snitch
BOOTROM_cva6   = cva
BOOTROM_veer   = veer
BOOTROM_mini   = mini
BOOTROM_vex    = vex
# VexiiRiscv: same rv32im bootrom as VexRiscv
BOOTROM_vex2   = vex
GEN_veer       = veer_snapshot/common_defines.vh
GEN_mini       = riscv_mini/Tile.sv
GEN_vex        = vexriscv/VexRiscvU55.v
GEN_vex2       = vexiiriscv/VexiiRiscvU55.v

.PHONY: all snitch cva veer mini vex vex2 bitgen sim-snitch sim-cva6 sim-veer sim-mini sim-vex sim-vex2 clean
# the generated sources are built by pattern rules: never delete them as intermediate files
.SECONDARY:

all:
	@echo "usage: make snitch | cva | veer | mini | vex | vex2 | bitgen [CORE=snitch|cva6|veer|mini|vex|vex2] | sim-snitch | sim-cva6 | sim-veer | sim-mini | sim-vex | sim-vex2 | clean"

# -----------------
# Vivado projects
# -----------------
snitch: project-snitch
cva:    project-cva6
veer:   project-veer
mini:   project-mini
vex:    project-vex
vex2:   project-vex2

.SECONDEXPANSION:
project-%: $$(BUILD_DIR)/$$*/bootrom/bootrom_$$(BOOTROM_$$*).sv $$(addprefix $$(BUILD_DIR)/$$*/,$$(GEN_$$*))
	$(PYTHON) -I tcl_scripts/filelists/gen_filelist.py $* --bootrom $< \
		--veer-snapshot $(BUILD_DIR)/$*/veer_snapshot --mini-rtl $(BUILD_DIR)/$*/riscv_mini/Tile.sv \
		--vex-rtl $(BUILD_DIR)/$*/vexriscv/VexRiscvU55.v --vex2-rtl $(BUILD_DIR)/$*/vexiiriscv/VexiiRiscvU55.v > $(BUILD_DIR)/$*/$*.f
	cd $(BUILD_DIR)/$* && $(VIVADO_BATCH) -log create_project.log \
		-source $(CURDIR)/tcl_scripts/create_project.tcl -tclargs $* $(BUILD_DIR)/$* $(BUILD_DIR)/$*/$*.f $(FREQ_CORE) $(FREQ_CLUSTER) $(FREQ_PERIPH) $(IP_CACHE)
	echo $* > $(BUILD_DIR)/.core

bitgen:
	@test -n "$(CORE)" || (echo "no project: run make snitch | cva | veer | mini | vex | vex2 first" && exit 1)
	@test -f $(BUILD_DIR)/$(CORE)/u55_$(CORE).xpr || (echo "missing $(BUILD_DIR)/$(CORE)/u55_$(CORE).xpr, run make first" && exit 1)
	cd $(BUILD_DIR)/$(CORE) && $(VIVADO_BATCH) -log run_impl.log \
		-source $(CURDIR)/tcl_scripts/run_impl.tcl -tclargs $(BUILD_DIR)/$(CORE)/u55_$(CORE).xpr $(JOBS) "$(SYNTH_STRATEGY)" "$(IMPL_STRATEGY)"

# -----------------
# Generated sources of a run: build/<run>/...
# -----------------
# bootrom_u55, one rule per bootrom core
define BOOTROM_RULE
$$(BUILD_DIR)/%/bootrom/bootrom_$(1).sv: $$(BOOTROM_SRCS)
	$$(MAKE) -C bootrom_u55 CORE=$(1) BUILD_DIR=$$(dir $$@) all
endef
$(foreach c,snitch cva veer mini vex,$(eval $(call BOOTROM_RULE,$(c))))

# VeeR-EL2 snapshot (VEER_CONFIG is in this Makefile)
$(BUILD_DIR)/%/veer_snapshot/common_defines.vh: Makefile
	rm -rf $(dir $@) && mkdir -p $(dir $@)
	cd $(VEER_ROOT) && RV_ROOT=$(VEER_ROOT) BUILD_PATH=$(dir $@) perl configs/veer.config $(VEER_CONFIG) > $(dir $@)/veer.config.log

# riscv-mini: chisel -> systemverilog with sbt (hw/cores/riscv-mini/Makefile), sbt caches stay in the submodule.
# Runs in parallel share the sbt project of the submodule: serialize them with a lock in its
# (git ignored) target directory
MINI_SBT_LOCK = $(MINI_ROOT)/target/.sbt.lock
$(BUILD_DIR)/%/riscv_mini/Tile.sv: $(MINI_SRCS)
	mkdir -p $(dir $@) $(dir $(MINI_SBT_LOCK))
	flock $(MINI_SBT_LOCK) $(MAKE) -C $(MINI_ROOT) compile gen_dir=$(dir $@) > $(dir $@)/sbt.log 2>&1 || (tail -20 $(dir $@)/sbt.log; exit 1)

# VexRiscv: SpinalHDL -> verilog with sbt, the generator (VEX_GEN) is compiled with the
# VexRiscv sources without copying it in the submodule (a single file: sbt source directories are
# recursive and hw/cores/vex holds the submodule). Serialized like riscv-mini
VEX_SBT_LOCK = $(VEX_ROOT)/target/.sbt.lock
$(BUILD_DIR)/%/vexriscv/VexRiscvU55.v: $(VEX_SRCS)
	mkdir -p $(dir $@) $(dir $(VEX_SBT_LOCK))
	cd $(VEX_ROOT) && flock $(VEX_SBT_LOCK) sbt -batch 'set Compile / unmanagedSources += file("$(VEX_GEN)")' \
		"runMain vexriscv.u55.GenVexRiscvU55 $(dir $@)" > $(dir $@)/sbt.log 2>&1 || (tail -20 $(dir $@)/sbt.log; exit 1)

# VexiiRiscv: same flow as VexRiscv. Its build compiles SpinalHDL from the ext/SpinalHDL submodule
# of VexiiRiscv (git submodule update --init ext/SpinalHDL ext/rvls in hw/cores/vex2/VexiiRiscv).
# tester/TestbenchServer.scala (simulation server, unused here) needs JDK 16+: not compiled
VEX2_SBT_LOCK = $(VEX2_ROOT)/target/.sbt.lock
$(BUILD_DIR)/%/vexiiriscv/VexiiRiscvU55.v: $(VEX2_SRCS)
	mkdir -p $(dir $@) $(dir $(VEX2_SBT_LOCK))
	cd $(VEX2_ROOT) && flock $(VEX2_SBT_LOCK) sbt -batch 'set Compile / unmanagedSources += file("$(VEX2_GEN)")' \
		'set Compile / unmanagedSources / excludeFilter := HiddenFileFilter || "TestbenchServer.scala"' \
		"runMain vexiiriscv.u55.GenVexiiRiscvU55 $(dir $@) $(VEX2_ARGS)" > $(dir $@)/sbt.log 2>&1 || (tail -20 $(dir $@)/sbt.log; exit 1)

# -----------------
# Simulations
# -----------------
sim-snitch: $(BUILD_DIR)/sim-snitch/bootrom/bootrom_snitch.sv
	$(MAKE) -C sim/snitch BUILD_DIR=$(BUILD_DIR)/sim-snitch BOOTROM=$<

sim-cva6: $(BUILD_DIR)/sim-cva6/bootrom/bootrom_cva.sv
	$(MAKE) -C sim/cva6 BUILD_DIR=$(BUILD_DIR)/sim-cva6 BOOTROM=$<

sim-veer: $(BUILD_DIR)/sim-veer/bootrom/bootrom_veer.sv $(BUILD_DIR)/sim-veer/veer_snapshot/common_defines.vh
	$(MAKE) -C sim/veer BUILD_DIR=$(BUILD_DIR)/sim-veer BOOTROM=$< VEER_SNAPSHOT=$(BUILD_DIR)/sim-veer/veer_snapshot

sim-mini: $(BUILD_DIR)/sim-mini/bootrom/bootrom_mini.sv $(BUILD_DIR)/sim-mini/riscv_mini/Tile.sv
	$(MAKE) -C sim/mini BUILD_DIR=$(BUILD_DIR)/sim-mini BOOTROM=$< MINI_RTL=$(BUILD_DIR)/sim-mini/riscv_mini/Tile.sv

sim-vex: $(BUILD_DIR)/sim-vex/bootrom/bootrom_vex.sv $(BUILD_DIR)/sim-vex/vexriscv/VexRiscvU55.v
	$(MAKE) -C sim/vex BUILD_DIR=$(BUILD_DIR)/sim-vex BOOTROM=$< VEX_RTL=$(BUILD_DIR)/sim-vex/vexriscv/VexRiscvU55.v

sim-vex2: $(BUILD_DIR)/sim-vex2/bootrom/bootrom_vex.sv $(BUILD_DIR)/sim-vex2/vexiiriscv/VexiiRiscvU55.v
	$(MAKE) -C sim/vex2 BUILD_DIR=$(BUILD_DIR)/sim-vex2 BOOTROM=$< VEX2_RTL=$(BUILD_DIR)/sim-vex2/vexiiriscv/VexiiRiscvU55.v

clean:
	rm -rf $(BUILD_DIR)
