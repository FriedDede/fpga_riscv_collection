![CI](https://github.com/pulp-platform/snitch_cluster/actions/workflows/ci.yml/badge.svg)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

# OPEN RISCV Cluster and core collection

This repository hosts the hardware and software for a RISCV core cluster for FPGA targets.
The repository want also to act as a library of ready to use, wrapped risc-v cores for any other project that may need them.

The platform targets the AMD Alveo U55C, and is based on PULP project infrastructure.
Supported cores are:
- Snitch, [original repo](https://github.com/pulp-platform/snitch_cluster) 
- CVA6, [original repo](https://github.com/openhwfoundation/cva6)
- VeeR-EL2,  [original repo](https://github.com/chipsalliance/Cores-VeeR-EL2)
- riscv-mini [original repo](https://github.com/ucb-bar/riscv-mini)
- VexRiscv [original repo](https://github.com/SpinalHDL/VexRiscv.git)
- VexiiRiscv [original repo](https://github.com/SpinalHDL/VexiiRiscv)

Each core is wrapped in a CORE_cd_wrapper, which wraps each core inside an isolated core clock domain, with clock domain converters on the core side and a standard interface with minimal variability across the cores:

    module CORE_cd_wrapper #(
        parameter int unsigned AxiAddrWidth = 32,
        parameter int unsigned AxiDataWidth = 64,
        parameter int unsigned AxiUserWidth = 1,
        parameter int unsigned AxiIdWidth   = 5,
        parameter int unsigned CdcLogDepth  = 2
    )(
        // core domain clock 
        input  logic        clk_core_i,
        input  logic        rst_ni,
        // outside domain clock
        input  logic        clk_cluster_i,
        input  logic        rst_cluster_ni,
        // HART ID (if supported)
        input  logic [63:0] hart_id_i,
        // Interrupts (if needed)       
        input  logic        timer_irq_i,
        input  logic        soft_irq_i,
        input  logic        ext_irq_i,     
        // axi memory channels
        AXI_BUS.Master      noc
    );

The cluster is organized in core complexes as in Figure, each complex has a bootrom and support multiple cores (cores in a complex should have unique HART IDs).

Complexes shares access to the board HBM with the host, which loads the software payload through PCIe (QDMA) and starts the cores.

![alt text](u55Cluster.drawio.png)

# Repository organization

## bootrom_u55
Initialization code for the riscv cores, compiled into an rtl bootrom, and its compile scripts.
`make -C bootrom_u55 CORE=<core> BUILD_DIR=<dir> all` builds `bootrom_<core>.elf/.bin/.img/.dump/.sv`
(module `bootrom_<core>`) in `<dir>`: `snitch` (rv32g), `cva` (rv64gc), `veer` (rv32imc, stack in
the DCCM), `mini` (rv32i, code at the reset pc 0x200), `vex` (rv32im, also used by VexiiRiscv). The top Makefile builds the bootrom of each
run in its folder, nothing is generated in `bootrom_u55`.

## hw
All the hardware of the compute platform, see [hw/README.md](hw/README.md):
- `hw/cluster`: the FPGA tops, the clock domain wrappers of the cores and the boot reset logic
- `hw/cores`: the cores (Snitch, CVA6, VeeR-EL2, riscv-mini, VexRiscv and VexiiRiscv as git submodules) and the FPU
- `hw/infra`: AXI, APB and register interfaces, common cells and peripherals from the PULP project

## sim
Xcelium testbenches of the Snitch (`sim/snitch`), CVA6 (`sim/cva6`), VeeR-EL2 (`sim/veer`),
riscv-mini (`sim/mini`), VexRiscv (`sim/vex`) and VexiiRiscv (`sim/vex2`) tops: the FPGA top is
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
(`riscv64-unknown-elf-`), for riscv-mini, VexRiscv and VexiiRiscv sbt and a JDK (11 or newer, the Chisel / SpinalHDL to Verilog
generation downloads its dependencies on the first run) and, for simulation, Xcelium.
Fetch the submodules first:

    git submodule update --init

Every output goes in `build/` (`BUILD_DIR=<dir>` to change it):

    make snitch | cva | veer | mini | vex | vex2 # Vivado project in build/<core>/u55_<core>.xpr
    make bitgen [CORE=<core>] [JOBS=8]    # synthesis, implementation and bitstream of the last (or given) project
    make sim-snitch                       # Snitch boot test in xcelium (bootrom -> DRAM payload, mul/div, fpu lsu port)
    make sim-cva6                         # CVA6 boot test in xcelium (bootrom -> DRAM payload, fpu, I$/D$ refills)
    make sim-veer                         # VeeR boot test in xcelium (bootrom -> DRAM payload, DCCM stack, DMA port, I$)
    make sim-mini                         # riscv-mini boot test in xcelium (bootrom -> DRAM payload, D$ write-back)
    make sim-vex                          # VexRiscv boot test in xcelium (bootrom -> DRAM payload, I$/D$, ecall, CLINT irqs)
    make sim-vex2                         # VexiiRiscv boot test in xcelium (bootrom -> DRAM payload, write-back D$ + cbo, ecall, CLINT irqs)
    make clean                            # remove build/

The clocks of the three domains (in MHz, default 50) are set when the project is created:

    make veer FREQ_CORE=80 FREQ_CLUSTER=100 FREQ_PERIPH=50

- `FREQ_CORE`: clock of every core, each core is in its own clock domain
- `FREQ_CLUSTER`: crossbar, bootrom, CLINT and HBM channel of each cluster
- `FREQ_PERIPH`: peripheral crossbar, UART, timer (and PLIC). This should be left to 50 MHz
  (`bootrom_u55/src/platform.h`)

The Vivado strategies of `make bitgen` (default: the Vivado defaults) are set with:

    make bitgen SYNTH_STRATEGY=Flow_PerfOptimized_high IMPL_STRATEGY=Performance_Explore

`make bitgen` leaves the bitstream `build/<core>/u55_<core>.bit` and the timing and utilization
reports in the same directory.

## Known good configurations
Configurations that meet timing on the whole design (setup and hold) after `make bitgen`, with
`FREQ_PERIPH=50`. Core n is `CORE_NUMBER` (cores per cluster), cluster n is `CLUSTER_NUMBER` (tops in
`hw/cluster/tops`).

| Core       | Core n | Cluster n | Core freq (MHz) | Cluster freq (MHz) | Synth strategy            | Impl strategy                  |
|------------|--------|-----------|-----------------|--------------------|---------------------------|--------------------------------|
| riscv-mini | 1      | 1         | 200             | 50                 | Vivado Synthesis Defaults | Vivado Implementation Defaults |
| riscv-mini | 1      | 1         | 250             | 250                | Flow_PerfOptimized_high   | Performance_Explore            |
| riscv-mini | 1      | 1         | 275             | 50                 | Flow_PerfOptimized_high   | Performance_ExtraTimingOpt     |
| CVA6       | 1      | 1         | 100             | 250                | Vivado Synthesis Defaults | Vivado Implementation Defaults |
| Snitch     | 1      | 1         | 50              | 250                | Vivado Synthesis Defaults | Vivado Implementation Defaults |
| VexRiscv   | 1      | 1         | 250             | 250                | Vivado Synthesis Defaults | Vivado Implementation Defaults |
| VexiiRiscv | 1      | 1         | 250             | 250                | Vivado Synthesis Defaults | Vivado Implementation Defaults |

    make mini FREQ_CORE=200 FREQ_CLUSTER=50 FREQ_PERIPH=50 && make bitgen
    make mini FREQ_CORE=250 FREQ_CLUSTER=250 FREQ_PERIPH=50 && \
        make bitgen SYNTH_STRATEGY=Flow_PerfOptimized_high IMPL_STRATEGY=Performance_Explore
    make mini FREQ_CORE=275 FREQ_CLUSTER=50 FREQ_PERIPH=50 && \
        make bitgen SYNTH_STRATEGY=Flow_PerfOptimized_high IMPL_STRATEGY=Performance_ExtraTimingOpt
    make cva FREQ_CORE=100 FREQ_CLUSTER=250 FREQ_PERIPH=50 && make bitgen
    make snitch FREQ_CORE=50 FREQ_CLUSTER=250 FREQ_PERIPH=50 && make bitgen
    make vex FREQ_CORE=250 FREQ_CLUSTER=250 FREQ_PERIPH=50 && make bitgen
    make vex2 FREQ_CORE=250 FREQ_CLUSTER=250 FREQ_PERIPH=50 && make bitgen

## Core utilization
Post implementation utilization of one core with its clock domain wrapper (`hw/cluster/cd_wrappers`:
core, its memories, the AXI clock domain crossings and the interrupt synchronizers), from
`build/<core>/utilization.rpt`. The device totals are those of the Alveo U55C (XCU55C).

| Core       | ISA                              | Build (core / cluster MHz) | LUTs   | FFs    | RAMB36 | RAMB18 | DSP | LUTs % |
|------------|----------------------------------|----------------------------|--------|--------|--------|--------|-----|--------|
| riscv-mini | RV32I_Zicsr                      | 275 / 50                   | 4731   | 3565   | 0      | 10     | 0   | 0.36   |
| VexRiscv   | RV32IM_Zicsr                     | 250 / 250                  | 2720   | 3374   | 2      | 9      | 4   | 0.21   |
| VexiiRiscv | RV32IM_Zicsr_Zifencei_Zicntr_Zicbom | 250 / 250               | 7671   | 7633   | 3      | 9      | 4   | 0.59   |
| Snitch     | RV32IMAFD_Zicsr                  | 50 / 250                   | 14828  | 9907   | 12     | 0      | 15  | 1.14   |
| CVA6       | RV64IMAFDC_Zicsr_Zifencei_Zcb    | 125 / 250                  | 31311  | 14680  | 84     | 0      | 27  | 2.40   |
| VeeR-EL2   | RV32IMC_Zicsr_Zifencei_Zba_Zbb_Zbc_Zbs | 80 / 250             | 37138  | 25308  | 20     | 6      | 4   | 2.85   |
| XCU55C     |                                  |                            | 1303680| 2607360| 2016   | 4032   | 9024|        |

ISA as configured in this repository:
- riscv-mini: privileged spec 1.7 (machine mode, see [hw/README.md](hw/README.md)), no M, A, C
- Snitch: `snitch_core_axi` with RVF and RVD, M in the shared multiplier/divider, no Snitch
  extensions (DMA, SSR, FREP, IPU)
- CVA6: `cv64a6_imafdc_sv39` configuration with M, S and U modes but no MMU (`CVA6ConfigMmuPresent = 0`)
- VeeR-EL2: `VEER_CONFIG` snapshot, machine mode only (no user mode), 16 PMP entries
- VexRiscv: GenFullNoMmuMaxPerf (RV32IM, 4 KiB I$ with dynamic target branch prediction, 8 KiB
  write-through D$, 64 bit cache memory interface, no MMU), machine mode only, see [hw/README.md](hw/README.md)
- VexiiRiscv: RV32IM + Zicntr, Zicbom (dual issue, 4 KiB I$, 8 KiB write-back D$, BTB + GShare + RAS,
  no MMU), machine mode only, see [hw/cores/vex2/DSE.md](hw/cores/vex2/DSE.md) for the pipeline options, see [hw/README.md](hw/README.md)
- A (Snitch, CVA6): the cores issue the atomics as AXI atomic operations (`aw_atop`), but the HBM
  channel ports of the block design have no `aw_atop`: an atomic to the DRAM reaches it as a plain
  write (an `axi_riscv_atomics` adapter before the HBM channel would be needed)

The rest of a 1x1 design is mostly the QDMA + HBM block design (`hbm_interface`): about 59k LUTs,
75k FFs, 81 RAMB36, 13 RAMB18 and 5 URAM, the same for every core.

Each run folder (`build/<core>` for a project, `build/sim-<core>` for a simulation) holds the
sources generated for it, rebuilt when their inputs change:
- `bootrom/`: `bootrom_<core>.elf/.bin/.img/.dump/.sv`
- `veer_snapshot/`: VeeR-EL2 configuration, from `VEER_CONFIG` in the Makefile (VeeR runs)
- `riscv_mini/`: riscv-mini `Tile.sv`, from its Chisel sources with sbt (riscv-mini runs)
- `vexriscv/`: `VexRiscvU55.v`, from the VexRiscv SpinalHDL sources with sbt (VexRiscv runs)
- `vexiiriscv/`: `VexiiRiscvU55.v`, from the VexiiRiscv SpinalHDL sources with sbt (VexiiRiscv runs)
