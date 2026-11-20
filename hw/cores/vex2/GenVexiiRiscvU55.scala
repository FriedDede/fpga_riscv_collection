// Copyright 2026 Politecnico di Milano.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
//
// Description: VexiiRiscv for the u55c clusters, sized like the VexRiscv configuration
//              (hw/cores/vex/GenVexRiscvU55.scala):
//              - RV32IM + Zicsr, Zifencei, Zicntr (mcycle/minstret), Zicbom (cbo.clean/flush/inval:
//                the D$ is write-back, the payload flushes what the host must see)
//              - machine mode only, mhartid from an input port (hartId), reset vector 0x0 (bootrom_u55)
//              - single issue, full bypassing, BTB + GShare + RAS branch prediction
//              - 4 KiB direct mapped I$, 8 KiB direct mapped write-back D$, 64 byte lines,
//                64 bit refill / writeback buses (a line in 8 beats)
//              - three AXI4 masters: FetchL1Axi4 (I$ refills, read only), LsuL1Axi4 (D$ refills and
//                writebacks) and LsuCachelessAxi4 (uncached io accesses, 32 bit)
//              - PMA: DRAM 0x8000_0000 (512 MiB) cacheable, bootrom executable (fetched through the I$),
//                CLINT and peripherals io
//              - memories initialized to zero (FPGA power-up value, no X in RTL simulation)
// Usage: compiled together with the VexiiRiscv sources (Makefile), run with
//        runMain vexiiriscv.u55.GenVexiiRiscvU55 <output directory> [VexiiRiscv options]
//        the options (ParamSimple, e.g. --decoders 2 --lanes 2 --with-late-alu) are applied over the
//        configuration below (make VEX2_ARGS="...")
// Author: Andrea Motta

package vexiiriscv.u55

import spinal.core._
import spinal.core.internals.{PhaseContext, PhaseNetlist}
import spinal.lib.bus.misc.SizeMapping
import spinal.lib.bus.tilelink.{M2sTransfers, SizeRange}
import spinal.lib.system.tag.{PmaRegion, PmaRegionImpl}
import vexiiriscv._

object GenVexiiRiscvU55 extends App {
  val targetDirectory = if (args.nonEmpty) args(0) else "."
  val extraArgs = args.drop(1)

  val param = new ParamSimple()
  param.xlen          = 32
  param.addISA("m", "zicntr", "zicbom")
  param.resetVector   = 0x00000000l
  param.withHartIdInput = true
  param.privParam.withSupervisor = false
  param.privParam.withUser       = false
  param.additionalPerformanceCounters = 0

  // pipeline: full bypassing (as VexRiscv), branch prediction
  param.allowBypassFrom = 0
  param.withBtb       = true
  param.withGShare    = true
  param.withRas       = true
  param.btbSets       = 256
  param.gshareBytes   = 1024
  param.divRadix      = 2

  // I$: 64 sets * 1 way * 64 B = 4 KiB
  param.fetchL1Enable        = true
  param.fetchL1Sets          = 64
  param.fetchL1Ways          = 1
  param.fetchMemDataWidthMin = 64
  // D$: 128 sets * 1 way * 64 B = 8 KiB, write-back
  param.lsuL1Enable          = true
  param.lsuL1Sets            = 128
  param.lsuL1Ways            = 1
  param.lsuMemDataWidthMin   = 64
  param.lsuL1RefillCount     = 1
  param.lsuL1WritebackCount  = 1

  param.fetchBus = FetchBusEnum.axi4
  param.lsuBus   = LsuBusEnum.axi4
  param.lsuL1Bus = LsuL1BusEnum.axi4

  // the caches, BTB and GShare are cleared after reset
  param.bootMemClear = true

  // command line overrides
  assert(new scopt.OptionParser[Unit]("GenVexiiRiscvU55") {
    help("help").text("prints this usage text")
    param.addOptions(this)
  }.parse(extraArgs, ()).nonEmpty, "bad VexiiRiscv options: " + extraArgs.mkString(" "))
  println("[GenVexiiRiscvU55] options: " + extraArgs.mkString(" "))

  def region(base: BigInt, size: BigInt, main: Boolean, exe: Boolean) = new PmaRegionImpl(
    mapping      = SizeMapping(base, size),
    isMain       = main,
    isExecutable = exe,
    transfers    = M2sTransfers(get = SizeRange.all, putFull = SizeRange.all)
  )
  // address map of hw/cluster/tops/u55_vex2_top.sv
  val regions = List[PmaRegion](
    region(0x80000000l, 0x20000000l, main = true,  exe = true),   // DRAM (HBM channel)
    region(0x00000000l, 0x00010000l, main = false, exe = true),   // bootrom
    region(0x02000000l, 0x0000C000l, main = false, exe = false),  // CLINT
    region(0x10000000l, 0x70000000l, main = false, exe = false)   // peripherals (PLIC, UART, timer)
  )

  // the memories (register file, I$/D$ ways, BTB, GShare) have no reset: initialize them to zero as
  // the FPGA BRAMs/LUTRAMs, no X in RTL simulation
  class PhaseZeroInitMems extends PhaseNetlist {
    override def impl(pc: PhaseContext): Unit = pc.walkDeclarations {
      case mem: Mem[_] if mem.initialContent == null =>
        mem.initBigInt(Seq.fill(mem.wordCount)(BigInt(0)))
      case _ =>
    }
  }

  SpinalConfig(targetDirectory = targetDirectory, inlineRom = true)
    .addTransformationPhase(new PhaseZeroInitMems)
    .generateVerilog {
      val plugins = param.plugins()
      ParamSimple.setPma(plugins, regions)
      VexiiRiscv(plugins).setDefinitionName("VexiiRiscvU55")
    }
}
