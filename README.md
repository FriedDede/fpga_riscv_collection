![CI](https://github.com/pulp-platform/snitch_cluster/actions/workflows/ci.yml/badge.svg)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

# RISCV core Cluster

This repository hosts the hardware and software for a RISCV core cluster, developed as part of my master thesis project.
It is based on the work of the PULP project, a joint effort between ETH Zurich and the University of Bologna.

The platform targets the AMD Alveo U55C: clusters of RISC-V cores (Snitch, CVA6, VeeR-EL2 or riscv-mini) share
the board HBM with the host, which loads the software payload through PCIe (QDMA) and releases the
cores from reset.

![alt text](u55Cluster.drawio.png)

# Repository organization

## bootrom_u55
Initialization code for the riscv cores, compiled into an rtl bootrom, and its compile scripts.
`make -C bootrom_u55 CORE=<core> BUILD_DIR=<dir> all` builds `bootrom_<core>.elf/.bin/.img/.dump/.sv`
(module `bootrom_<core>`) in `<dir>`: `snitch` (rv32g), `cva` (rv64gc), `veer` (rv32imc, stack in
the DCCM), `mini` (rv32i, code at the reset pc 0x200). The top Makefile builds the bootrom of each
run in its folder, nothing is generated in `bootrom_u55`.

## hw
All the hardware of the compute platform, see [hw/README.md](hw/README.md):
- `hw/cluster`: the FPGA tops, the clock domain wrappers of the cores and the boot reset logic
- `hw/cores`: the cores (Snitch, CVA6, VeeR-EL2 and riscv-mini as git submodules) and the FPU
- `hw/infra`: AXI, APB and register interfaces, common cells and peripherals from the PULP project

## sim
Xcelium testbenches of the VeeR-EL2 (`sim/veer`) and riscv-mini (`sim/mini`) tops: the FPGA top is
simulated as is, with models of the HBM/QDMA block design and of the clock wizards (`sim/models`),
and boots a test payload from DRAM.

## sw
Git submodule with the riscv test executables, the cross compile toolchain and the host side
utilities to load the payload in the HBM.

## tcl_scripts
Vivado project generation (`create_project.tcl`), implementation (`run_impl.tcl`), clock wizards
(`gen_clock.tcl`), the QDMA + HBM block design (`qdma_interface.tcl`), the rtl filelist generator
(`filelists/gen_filelist.py`) and the flash programming script (`build_mcs.tcl`),
see [tcl_scripts/README.md](tcl_scripts/README.md).

## xdc
Alveo U55C constraints (`xdc/u55/u55_snitch_const.xdc`, shared by all the tops) and the clock domain
crossing constraints (`xdc/u55/u55_clock_domains.tcl`).

# Build
Requires Vivado 2024.2 (with the Alveo U55C board files), the riscv gcc toolchain
(`riscv64-unknown-elf-`), for riscv-mini sbt and a JDK (11 or newer, the Chisel to SystemVerilog
generation downloads its dependencies on the first run) and, for simulation, Xcelium.
Fetch the submodules first:

    git submodule update --init

Every output goes in `build/` (`BUILD_DIR=<dir>` to change it):

    make snitch | cva | veer | mini       # Vivado project in build/<core>/u55_<core>.xpr
    make bitgen [CORE=<core>] [JOBS=8]    # synthesis, implementation and bitstream of the last (or given) project
    make sim-veer                         # VeeR boot test in xcelium (bootrom -> DRAM payload, DCCM stack, DMA port, I$)
    make sim-mini                         # riscv-mini boot test in xcelium (bootrom -> DRAM payload, D$ write-back)
    make clean                            # remove build/

The clocks of the three domains (in MHz, default 50) are set when the project is created:

    make veer FREQ_CORE=80 FREQ_CLUSTER=100 FREQ_PERIPH=50

- `FREQ_CORE`: clock of every core, each core is in its own clock domain
- `FREQ_CLUSTER`: crossbar, bootrom, CLINT and HBM channel of each cluster
- `FREQ_PERIPH`: peripheral crossbar, UART, timer (and PLIC). This should be left to 50 MHz
  (`bootrom_u55/src/platform.h`)

`make bitgen` leaves the bitstream `build/<core>/u55_<core>.bit` and the timing and utilization
reports in the same directory.

Each run folder (`build/<core>` for a project, `build/sim-<core>` for a simulation) holds the
sources generated for it, rebuilt when their inputs change:
- `bootrom/`: `bootrom_<core>.elf/.bin/.img/.dump/.sv`
- `veer_snapshot/`: VeeR-EL2 configuration, from `VEER_CONFIG` in the Makefile (VeeR runs)
- `riscv_mini/`: riscv-mini `Tile.sv`, from its Chisel sources with sbt (riscv-mini runs)
