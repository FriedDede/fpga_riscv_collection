// Copyright 2026 Politecnico di Milano.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
//
// Description: VexRiscv for the u55c clusters: the GenFullNoMmuMaxPerf configuration
//              (hw/cores/vex/VexRiscv/src/main/scala/vexriscv/demo/GenFullNoMmuMaxPerf.scala) with
//              - reset vector 0x0 (bootrom_u55) instead of 0x8000_0000 (IBusCachedPlugin)
//              - uncached (io) region: everything below the DRAM (0x8000_0000)
//              - CSRs: CsrPluginConfig.small plus writable mtvec, mhartid from an input port
//                (hartId), ecall/ebreak, illegal csr trap, read only mcycle/minstret
//              - no DebugPlugin (no debug module in the u55c clusters)
//              - 4 KiB I$ (8 KiB upstream)
//              - 64 bit cache memory interface (32 bit upstream): line refills in 4 beats
//              - AXI4 masters: iBusAxi (read only) and dBusAxi, 64 bit data, no id
//              - memories initialized to zero (FPGA power-up value, no X in RTL simulation)
//              RV32IM, 4 KiB direct mapped I$ (dynamic target branch prediction) and
//              8 KiB direct mapped write-through D$, 32 byte lines.
// Usage: compiled together with the VexRiscv sources (Makefile), run with
//        runMain vexriscv.u55.GenVexRiscvU55 <output directory>
// Author: Andrea Motta

package vexriscv.u55

import spinal.core._
import spinal.core.internals.{PhaseContext, PhaseNetlist}
import spinal.lib._
import spinal.lib.bus.amba4.axi.{Axi4ReadOnly, Axi4, Axi4Shared}
import vexriscv.ip.{DataCacheConfig, DataCacheMemBus, InstructionCacheConfig}
import vexriscv.plugin._
import vexriscv.{VexRiscv, VexRiscvConfig, plugin}

object GenVexRiscvU55 extends App {
  val targetDirectory = if (args.nonEmpty) args(0) else "."

  // DataCacheMemBus.toAxi4Shared with memDataWidth > cpuDataWidth: the commands carry cpuDataWidth
  // write data (the write-through D$ only issues single beat writes), replicated on the memory
  // bus lanes with the byte enables of the addressed lane. Reads (refills and uncached) already
  // return memDataWidth data. Same ordering rules as upstream: a read waits for the pending writes
  def dBusToAxi4Shared(bus: DataCacheMemBus, pendingWritesMax: Int = 7): Axi4Shared = new Area {
    setName("dBusToAxi4Shared")
    val p = bus.p
    val axi = Axi4Shared(p.getAxi4SharedConfig()).setName("dbus_axi")

    val pendingWrites = CounterUpDown(
      stateCount = pendingWritesMax + 1,
      incWhen = bus.cmd.fire && bus.cmd.wr,
      decWhen = axi.writeRsp.fire
    )

    val hazard = (pendingWrites =/= 0 && !bus.cmd.wr) || pendingWrites === pendingWritesMax
    val (cmdFork, dataFork) = StreamFork2(bus.cmd.haltWhen(hazard))
    val cmdStage  = cmdFork.throwWhen(RegNextWhen(!cmdFork.last, cmdFork.fire).init(False))
    val dataStage = dataFork.throwWhen(!dataFork.wr)

    axi.sharedCmd.arbitrationFrom(cmdStage)
    axi.sharedCmd.write := cmdStage.wr
    axi.sharedCmd.prot := "010"
    axi.sharedCmd.cache := "1111"
    axi.sharedCmd.size :=
      cmdStage.uncached ? cmdStage.size.resized | U(log2Up(p.memDataBytes), axi.sharedCmd.size.getWidth bits)
    axi.sharedCmd.addr := cmdStage.address
    axi.sharedCmd.len  := cmdStage.beatCountMinusOne.resized

    val lanes = p.memDataWidth / p.cpuDataWidth
    val lane  = dataStage.address(log2Up(p.memDataBytes) - 1 downto log2Up(p.cpuDataBytes))
    axi.writeData.arbitrationFrom(dataStage)
    axi.writeData.data := Cat(List.fill(lanes)(dataStage.data))
    axi.writeData.strb := (dataStage.mask.resize(p.memDataBytes) << (lane * p.cpuDataBytes)).resize(p.memDataBytes)
    axi.writeData.last := dataStage.last

    bus.rsp.valid := axi.r.valid
    bus.rsp.error := !axi.r.isOKAY()
    bus.rsp.data := axi.r.data

    axi.r.ready := True
    axi.b.ready := True
  }.axi

  def cpu() = {
    val config = VexRiscvConfig(
      plugins = List(
        // PcManagerSimplePlugin of GenFullNoMmuMaxPerf is an empty legacy plugin: the reset
        // vector is a parameter of the fetcher (IBusCachedPlugin)
        new IBusCachedPlugin(
          resetVector = 0x00000000l,
          prediction = DYNAMIC_TARGET,
          historyRamSizeLog2 = 8,
          config = InstructionCacheConfig(
            cacheSize = 4096,
            bytePerLine =32,
            wayCount = 1,
            addressWidth = 32,
            cpuDataWidth = 32,
            memDataWidth = 64,
            catchIllegalAccess = true,
            catchAccessFault = true,
            asyncTagMemory = false,
            twoCycleRam = false,
            twoCycleCache = true
          )
        ),
        new DBusCachedPlugin(
          config = new DataCacheConfig(
            cacheSize         = 4096*2,
            bytePerLine       = 32,
            wayCount          = 1,
            addressWidth      = 32,
            cpuDataWidth      = 32,
            memDataWidth      = 64,
            catchAccessError  = true,
            catchIllegal      = true,
            catchUnaligned    = true
          )
        ),
        // bootrom, clint and peripherals (< 0x8000_0000) are not cacheable
        new StaticMemoryTranslatorPlugin(
          ioRange      = _.msb === False
        ),
        new DecoderSimplePlugin(
          catchIllegalInstruction = true
        ),
        new RegFilePlugin(
          regFileReadyKind = plugin.SYNC,
          zeroBoot = false
        ),
        new IntAluPlugin,
        new SrcPlugin(
          separatedAddSub = false,
          executeInsertion = true
        ),
        new FullBarrelShifterPlugin(earlyInjection = true),
        new HazardSimplePlugin(
          bypassExecute           = true,
          bypassMemory            = true,
          bypassWriteBack         = true,
          bypassWriteBackBuffer   = true,
          pessimisticUseSrc       = false,
          pessimisticWriteRegFile = false,
          pessimisticAddressMatch = false
        ),
        new MulPlugin,
        new DivPlugin,
        new CsrPlugin(CsrPluginConfig.small(0x00000000l).copy(
          catchIllegalAccess  = true,
          mtvecAccess         = CsrAccess.READ_WRITE,
          withExternalMhartid = true,
          mhartidWidth        = 32,
          ecallGen            = true,
          ebreakGen           = true,
          mcycleAccess        = CsrAccess.READ_ONLY,
          minstretAccess      = CsrAccess.READ_ONLY
        )),
        new BranchPlugin(
          earlyBranch = false,
          catchAddressMisaligned = true
        )
      )
    )

    val cpu = new VexRiscv(config)
    cpu.setDefinitionName("VexRiscvU55")
    cpu.rework {
      for (p <- config.plugins) p match {
        case p: IBusCachedPlugin =>
          p.iBus.setAsDirectionLess()
          master(p.iBus.toAxi4ReadOnly().toFullConfig()).setName("iBusAxi")
        case p: DBusCachedPlugin =>
          p.dBus.setAsDirectionLess()
          master(dBusToAxi4Shared(p.dBus).toAxi4().toFullConfig()).setName("dBusAxi")
        case p: CsrPlugin =>
          p.externalMhartId.setName("hartId")
        case _ =>
      }
    }
    cpu
  }

  // the memories (register file, I$/D$ ways, branch history) have no reset: initialize them to
  // zero as the FPGA BRAMs/LUTRAMs, otherwise the X of the uninitialized branch history corrupts the
  // pipeline flushes in RTL simulation
  class PhaseZeroInitMems extends PhaseNetlist {
    override def impl(pc: PhaseContext): Unit = pc.walkDeclarations {
      case mem: Mem[_] if mem.initialContent == null =>
        mem.initBigInt(Seq.fill(mem.wordCount)(BigInt(0)))
      case _ =>
    }
  }

  SpinalConfig(targetDirectory = targetDirectory, inlineRom = true)
    .addTransformationPhase(new PhaseZeroInitMems)
    .generateVerilog(cpu())
}
