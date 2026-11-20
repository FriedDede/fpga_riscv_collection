# VexiiRiscv design space exploration

Pipeline options of VexiiRiscv (`ParamSimple`, passed with `make VEX2_ARGS="..."` over
`GenVexiiRiscvU55.scala`) for the u55c tops at **250 MHz core / 250 MHz cluster**. The aim is to
find the highest IPC that still meets timing at 250 MHz.

**Result:** the Makefile default is the `dat2_rb_la` configuration:

    --decoders 2 --lanes 2 --with-late-alu --regfile-async --allow-bypass-from 0 --dispatcher-at 2 --relaxed-branch

It gets 1.055 IPC (1.43x single issue VexiiRiscv, 1.57x VexRiscv) and meets 250 MHz with
+0.076 ns on the core clock. `VEX2_ARGS=` builds the single issue configuration of the .scala.

## Setup

Every configuration keeps the rest of `GenVexiiRiscvU55.scala`:
- RV32IM + Zicntr, Zicbom.
- 4 KiB direct mapped I$ and 8 KiB direct mapped write-back D$.
- BTB (256 sets), GShare (1 KiB) and RAS.

**IPC:** measured in xcelium on the FPGA top (`make sim-vex2 TEST=../bench/bench.c CORE_PERIOD=4ns
CLUSTER_PERIOD=4ns MAX_CYCLES=50000000`) with [sim/bench/bench.c](../../../sim/bench/bench.c).
- Nine kernels; each runs once to warm the caches and predictors, then again measured with
  `mcycle` / `minstret`.
- Every configuration retires the same 234036 instructions with the same checksums.
- The HBM is the simulation model, so the stream kernels (32 KiB, larger than the D$) depend on
  its latency.

**Timing:** `make vex2 FREQ_CORE=250 FREQ_CLUSTER=250 FREQ_PERIPH=50 && make bitgen`, with the
default Vivado strategies, one 1x1 run each (no seed sweep).
- Slack is on the core clock (`core_clk_0_xlnx_clk_gen_cluster`). The rest of the design
  (shell, HBM AXI clock) sits at about +0.01 ns in every run, independently of the core.
- LUTs and FFs: `vex2_cd_wrapper` = the core plus AXI CDCs and width converters.
- Differences of a few tens of ps between runs are within place-and-route noise.

## Configurations

All dual issue configurations use `--decoders 2 --lanes 2 --regfile-async --allow-bypass-from 0`.

| name       | options added                                   | IPC       | core slack     | wrapper LUTs | wrapper FFs | core LUTs | RAMB36 / RAMB18 / DSP |
|------------|-------------------------------------------------|-----------|----------------|--------------|-------------|-----------|-----------------------|
| vex        | VexRiscv (`hw/cores/vex`), for reference        | 0.670     | met            | 2720         | 3374        |           | 2 / 9 / 4             |
| vex2       | single issue (`VEX2_ARGS=`)                     | 0.738     | +0.074 ns (*)  | 4598         | 6158        |           | 2 / 9 / 4             |
| dual       | `--with-late-alu`                               | **1.062** | +0.003 ns      | 7573         | 7475        | 5623      | 3 / 9 / 4             |
| dual_nola  | (none: no late ALU)                             | 0.873     | +0.063 ns      | 6339         | 6566        | 4389      | 3 / 9 / 4             |
| relaxed    | `--with-late-alu --relaxed-btb --relaxed-branch` | 0.916    | +0.012 ns      | 7571         | 7507        | 5624      | 3 / 9 / 4             |
| dat2       | `--with-late-alu --dispatcher-at 2`             | 1.058     | **-0.034 ns**  | 7777         | 7620        | 5826      | 3 / 9 / 4             |
| dat2_rb    | `--dispatcher-at 2 --relaxed-branch`            | 0.868     | +0.301 ns      | 6449         | 6927        | 4488      | 3 / 9 / 4             |
| **dat2_rb_la** | `--with-late-alu --dispatcher-at 2 --relaxed-branch` | 1.055 | **+0.076 ns** | 7671     | 7633        | 5728      | 3 / 9 / 4             |

(*) worst slack of the whole design; that run was not kept, so the core clock alone is unknown.

### IPC per kernel

| kernel    | vex   | vex2  | dual  | dual_nola | relaxed | dat2  | dat2_rb | dat2_rb_la |
|-----------|-------|-------|-------|-----------|---------|-------|---------|------------|
| crc32     | 0.940 | 0.983 | 1.398 | 1.339     | 1.124   | 1.397 | 1.338   | 1.397      |
| copy      | 0.646 | 0.628 | 1.053 | 0.632     | 0.955   | 1.050 | 0.626   | 1.035      |
| matmul    | 0.876 | 0.869 | 1.129 | 0.892     | 0.988   | 1.119 | 0.879   | 1.108      |
| sort      | 0.752 | 0.747 | 1.415 | 0.985     | 1.151   | 1.402 | 0.974   | 1.401      |
| chase     | 0.856 | 0.849 | 0.852 | 0.990     | 0.990   | 0.851 | 0.986   | 0.849      |
| fib       | 0.841 | 0.986 | 1.341 | 1.341     | 1.068   | 1.332 | 1.313   | 1.313      |
| div       | 0.107 | 0.107 | 0.110 | 0.108     | 0.109   | 0.110 | 0.108   | 0.110      |
| stream_rd | 0.400 | 0.454 | 0.725 | 0.505     | 0.676   | 0.725 | 0.505   | 0.724      |
| stream_rw | 0.539 | 0.679 | 1.040 | 0.773     | 0.887   | 1.040 | 0.772   | 1.040      |
| **total** | 0.670 | 0.738 | 1.062 | 0.873     | 0.916   | 1.058 | 0.868   | 1.055      |

## What each option does here

- **`--decoders 2 --lanes 2`** (dual issue): +44% IPC over single issue. Biggest gains are on
  `sort`, `copy`, `stream_*` and `fib`.
  - `div` is bound by the radix-2 divider.
  - `chase` is bound by the load-to-use latency.
- **`--with-late-alu`**: a second ALU at the end of execute, so an ALU instruction that depends on a
  load or on the other lane can still issue in the same cycle. Without it dual issue loses most of
  its gain on memory code: `copy` 1.05 -> 0.63 (single issue level), `sort` 1.42 -> 0.98,
  `stream_rd` 0.73 -> 0.51. Total 1.062 -> 0.873. It costs about 1100 LUTs in the core and
  lengthens the bypass network.
- **`--relaxed-btb`**: adds a cycle between the BTB read and its use in fetch. It costs about 14%
  IPC (with `--relaxed-branch`: 1.062 -> 0.916, on every branchy kernel). At 250 MHz its path
  (BTB -> GShare, +0.084 ns in `dual`) is not critical, so it is not used.
- **`--relaxed-branch`**: resolves branches one stage later (redirect registered). It costs about
  0.3% IPC (dat2 1.058 -> dat2_rb_la 1.055). It moves the execute -> GShare / BTB / PC redirect
  paths out of the critical set (-0.002 ns in `dat2` -> +0.13 to +0.25 ns in `dat2_rb_la`).
- **`--dispatcher-at 2`**: moves the dispatcher one stage later, cutting decode -> execute (the
  critical path of `dual`, +0.003 ns -> +0.13 ns). About -0.3% IPC. Alone (`dat2`) it fails at
  -0.034 ns: the execute paths it exposes (lane 0 -> lane 1 bypass, branch redirect) become
  critical, and they need `--relaxed-branch`.
- **`--with-dispatcher-buffer`** (not tried): adds lanes - 1 buffer slots to the dispatcher. It is
  an IPC feature (dispatch when one lane is blocked), it does not cut timing paths.

## Critical paths

Worst core-clock paths of each run, grouped by start -> end pipeline stage (paths with < 0.4 ns
slack, extracted from the routed checkpoint).

**dual** (+0.003 ns): about four path families within 0.1 ns of each other.
- decode -> execute, +0.003 ns, 248 paths: `decode_ctrls_1 Decode_INSTRUCTION` -> execute
  `SrcPlugin SRC1/SRC2`, `RS1`. 11-12 levels, about 2.8 ns of routing.
- decode -> regfile: +0.027 ns.
- execute -> BTB / GShare BRAM address (branch redirect): +0.055 ns.
- BTB -> GShare: +0.084 ns.

**relaxed** (+0.012 ns): decode -> execute is still the limit. The redirect paths it relaxes improve
(execute -> GShare +0.155 ns, execute -> BTB +0.322 ns), so the 14% IPC loss buys nothing at
250 MHz.

**dat2** (-0.034 ns, fails): decode -> execute improves to +0.024 ns, but execute -> execute
becomes the worst.
- execute -> execute, -0.034 ns, 113 paths: `execute_ctrl1 RD_PHYS_lane0` -> `early1_SrcPlugin_SRC1_lane1`.
  This is the lane 0 -> lane 1 hazard / bypass select, 11 levels.
- execute -> GShare: -0.002 ns.
- execute -> PcPlugin: +0.003 ns.

**dat2_rb** (+0.301 ns, no late ALU): the core is smaller and every family gains about 0.3 ns. The
worst path is BTB -> GShare / fetch / PC (+0.30 ns, the path of `--relaxed-btb`). The lane bypass
is at +0.34 ns. About 270 MHz is possible, but at 0.868 IPC it would need about 306 MHz to match
`dual` at 250 MHz.

**dat2_rb_la** (+0.076 ns, default):
- execute -> regfile read / operand registers, +0.076 to +0.080 ns, 180 paths:
  `execute_ctrl2 RD_PHYS_lane0` -> async regfile read (`RS1/RS2_lane0`) and the `SrcPlugin`
  operand registers. This is the bypass hazard check, 10-11 levels.
- execute -> GShare and decode -> execute: +0.132 ns.
- execute -> BTB: +0.161 ns.
- execute -> PC / fetch: +0.22 to +0.25 ns.

**dual_nola** (+0.063 ns, no late ALU): decode -> execute is the limit again.
- decode -> execute, +0.063 ns: `decode_ctrls_1 Decode_INSTRUCTION` -> `SrcPlugin SRC1_lane0`.
- decode -> regfile: +0.092 ns.
- execute -> GShare: +0.125 ns.
- The lane bypass (execute -> execute) moves out to +0.32 ns.

Dropping the late ALU alone gives only 60 ps more than `dual` and loses 18% IPC. The late ALU
lengthens the execute bypass, not the decode -> execute path, so `--dispatcher-at 2` is still
needed for margin.

## Going above 250 MHz

All families of `dat2_rb_la` are within about 0.1 ns, so a higher clock needs the bypass network
shortened as well:
- raise `--allow-bypass-from` (fewer bypass sources), or drop `--with-late-alu` (see `dat2_rb`:
  +0.3 ns but -18% IPC);
- then `--relaxed-btb` for the BTB -> GShare / fetch path, which costs 14% IPC.

`dat2_rb` shows the cost: without the late ALU the IPC drops more than the clock gains. At 250 MHz
`dat2_rb_la` is the best trade-off measured.

## Reproduce

    # IPC (one BUILD_DIR per configuration)
    make sim-vex2 BUILD_DIR=$PWD/build/<name> VEX2_ARGS="<options>" TEST=../bench/bench.c \
        CLUSTER_PERIOD=4ns CORE_PERIOD=4ns MAX_CYCLES=50000000
    grep BENCH build/<name>/sim-vex2/bench.log     # BENCH <kernel> <cycles> <instret> <checksum>, hex
    # timing and utilization
    make vex2 BUILD_DIR=$PWD/build/<name> VEX2_ARGS="<options>" FREQ_CORE=250 FREQ_CLUSTER=250 FREQ_PERIPH=50
    make bitgen BUILD_DIR=$PWD/build/<name> CORE=vex2
    # build/<name>/vex2/timing_summary.rpt, utilization.rpt
