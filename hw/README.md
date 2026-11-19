# TOKI RISC-V cluster Hardware

The `hw` directory contains the hardware of the compute platform, organized in three folders:

| Folder        | Content |
|---------------|---------|
| `cluster/`    | FPGA integration: tops, clock domain wrappers of the cores, boot reset logic |
| `cores/`      | the cores and their dependencies |
| `infra/`      | interconnect, common cells and peripherals (PULP project) |

The rtl files of a top are not listed by hand: `tcl_scripts/filelists/gen_filelist.py` follows the
module, interface and package references of the top and emits the filelist used by Vivado and Xcelium,
so a new file in these folders is picked up as soon as it is instantiated.

## cluster

| Path                         | Content |
|------------------------------|---------|
| `tops/u55_snitch_top.sv`     | Snitch top (`snitch_u55_xilinx_bd`) |
| `tops/u55_cva6_top.sv`       | CVA6 top (`cva6_u55_xilinx_bd`) |
| `tops/u55_VeeR_top.sv`       | VeeR-EL2 top (`veer_u55_xilinx_bd`) |
| `tops/u55_mini_top.sv`       | riscv-mini top (`mini_u55_xilinx_bd`) |
| `tops/*_sim.sv`              | older simulation tops, not used by the build flow (testbenches are in `sim/`) |
| `cd_wrappers/<core>_cd_wrapper.sv` | each core in its own clock domain (see below) |
| `cd_wrappers/cluster_clk_gen.sv`   | clock generator of a cluster: crossbar clock + one clock per core |
| `cd_wrappers/veer_fpga_mem.sv`, `veer_fpga_sram.sv` | VeeR DCCM / I$ (/ ICCM) memories as BRAM |
| `xdma_boot/axi4_boot_check.v` | host reset checker, module of the QDMA/HBM block design |

## cores

| Path              | Content |
|-------------------|---------|
| `snitch/`         | Snitch core, cluster packages, icache, SSR, IPU, VM, FP div/sqrt |
| `cva6/`           | CVA6 (`cva6_config_pkg`: rv64, 32 bit AXI address, write through cache) |
| `fpnew/`          | FPU of Snitch and CVA6 |
| `riscv-mini/`     | riscv-mini (RV32I, Chisel), git submodule of [ucb-bar/riscv-mini](https://github.com/ucb-bar/riscv-mini). Its `Tile.sv` is generated in the run folder (`build/<run>/riscv_mini`) by the Makefile (sbt) |
| `Cores-VeeR-EL2/` | VeeR-EL2, git submodule of [chipsalliance/Cores-VeeR-EL2](https://github.com/chipsalliance/Cores-VeeR-EL2). Its configuration (snapshot) is generated in the run folder (`build/<run>/veer_snapshot`) from `VEER_CONFIG` in the Makefile |

## infra

`apb`, `axi_pulp`, `axi_riscv_atomics`, `axi_stream`, `axi_tools` (HBM channel macros),
`common_cells`, `mem_interface`, `register_interface`, `reqrsp_interface`, `riscv_dbg`, `scm`,
`tcdm_interface`, `tech_cells` and `axi_pheripherals` (CLINT, PLIC, UART, timer, AXI to APB).
Each IP is structured as:
  - `src`: RTL sources
  - `include`: RTL headers if existing
  - `test`: standalone testbenches if existing
  - `doc`, `util`: documentation and helper scripts if existing

# Architecture

Each top has `CLUSTER_NUMBER` clusters of `CORE_NUMBER` cores (1x1 by default):

    core 0..N-1 ──axi_cdc──┐
                           ├── cluster crossbar ── bootrom, CLINT
                           │                    ── HBM channel S<i> (qdma_interface.tcl)
                           │                    ── axi_cdc ── peripheral crossbar ── UART, timer (PLIC)
    host (PCIe/QDMA) ───────────────────────────── HBM, reset of the clusters (master_areset)

## Clock domains
- **core**: every core is its own clock domain. `cd_wrappers/<core>_cd_wrapper.sv` contains the
  core, its reset synchronizer, an `axi_cdc` on each AXI port and a synchronizer on each interrupt:
  the wrapper ports are the core clock, the asynchronous soc reset, the cluster clock and reset,
  the interrupts (from any domain) and the AXI ports in the cluster domain.
- **cluster**: crossbar, bootrom, CLINT and HBM channel of each cluster. Each cluster has its own
  MMCM (`cluster_clk_gen`, `xlnx_clk_gen_cluster`): the cluster clock and up to 6 core clocks.
- **peripherals**: peripheral crossbar, UART, timer (and PLIC), one MMCM (`xlnx_clk_gen_periph`).
- **HBM**: each HBM channel (`axi_clk_cluster_S<i>` port of the block design) runs at the clock of its
  cluster crossbar, the block design SmartConnect crosses it to the HBM clock.

All these clocks are asynchronous to each other (`xdc/u55/u55_clock_domains.tcl`). The U55C has 12
MMCMs: one is used by the block design and one by the peripherals, at most 10 clusters fit.
The soc reset (PLL lock, board reset, `master_areset` from the host) is asserted asynchronously and
released by a `rstgen` in each domain. Hart ids restart from 0 in each cluster.

## HBM channels
The tops connect the clusters to the `hbm_interface` block design with the macros of
`infra/axi_tools/hbm_axi.svh`:

    hbm_interface i_hbm_interface (
        `HBM_ASSIGN_CHANNEL(S00, axi_dram[0], 0, clk_cluster[0]),  // bus, HBM 1GB segment, bus clock
        `HBM_TIE_OFF_CHANNEL(S01, clk_cluster[0]),                 // unused, needs a running clock
        ...

## Adding a core
1. add the core sources in `cores/`
2. write `cluster/cd_wrappers/<core>_cd_wrapper.sv` with the same ports as the existing wrappers
3. copy one of the tops in `cluster/tops/` and instantiate the wrapper in `core_gen`
4. add the core to `CORES` in `tcl_scripts/filelists/gen_filelist.py`, to `top_module` in
   `tcl_scripts/create_project.tcl` and a `make <core>` target in the Makefile

# Memory maps

## Snitch, CVA6 and riscv-mini
| Range                     | Target |
|---------------------------|--------|
| 0x0000_0000 - 0x0000_FFFF | bootrom |
| 0x0200_0000 - 0x0200_BFFF | CLINT |
| 0x1000_0000 - 0x13FF_FFFF | PLIC |
| 0x1400_0000 - 0x1400_0FFF | UART |
| 0x1400_1000 - 0x1400_1FFF | timer |
| 0x8000_0000 - 0x9FFF_FFFF | DRAM (HBM channel of the cluster) |

## VeeR-EL2
| Range                     | Target |
|---------------------------|--------|
| 0x0000_0000 - 0x0000_FFFF | bootrom (`bootrom_veer`, bootrom_u55 `CORE=veer`) |
| 0x0200_0000 - 0x0200_BFFF | CLINT |
| 0x1400_0000 - 0x1400_0FFF | UART |
| 0x1400_1000 - 0x1400_1FFF | timer |
| 0x6000_0000 - 0x7FFF_FFFF | VeeR DMA port (to core 0 of the cluster): DCCM at 0x7004_0000 |
| 0x8000_0000 - 0x9FFF_FFFF | DRAM (HBM channel of the cluster) |
| 0xF004_0000 - 0xF004_FFFF | DCCM 64KB (core local), the bootrom puts the stack at its end |
| 0xF00C_0000               | VeeR PIC: UART = source 1, timers = sources 2..5 |

## VeeR-EL2 notes

VeeR has no PLIC: the UART and timer interrupts go to its internal PIC. The bootrom sets the region
access control (`mrac`): regions 0x0 and 0x1 (bootrom, CLINT, peripherals) side effect,
region 0x8 (DRAM) cacheable. The ICCM is disabled in `VEER_CONFIG`: when enabled it is at
0xEE00_0000, the core can only execute from it and it is written through the DMA port (0x6E00_0000).

## riscv-mini notes
riscv-mini follows the privileged spec 1.7: reset pc 0x200, read-only `mtvec` (0x100) with the
machine mode trap vector at 0x1c0, `mhartid` is csr 0xf10 and always 0 (one core per cluster),
`mtohost` / `mfromhost` (0x780 / 0x781) are not connected. It has no external interrupts (CLINT and
PLIC are not connected to the core) and its I$ and D$ (4KB, direct mapped) have no uncached path:
the D$ is write-back, so stores to the peripherals and to the DRAM shared with the host reach
the bus only when the line is evicted.
