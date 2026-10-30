# HBM teasting HW side for ALVEO U55C
## This folder contains:
    gen_clock.tcl           // generates clock primitives for compute subsystem
    hbm_interface.tcl       // legacy xdma version of the bd (Vivado 2023.2), not used by the tops
    xdc/u55_const.xdc           // constraint file
    xdma_boot/axi_boot_check.v        // Verilog module triggers master reset when host sends reset code
    xdma_boot/tb_axi_boot_check.v     // His validation testbench (validated in xcelium)
    build_mcs.tcl           // build mcs and loads it on alveo u55c
    qdma_interface.tcl      // qdma + hbm block design (hbm_interface), used by create_project.tcl
    create_project.tcl      // creates the vivado project of a core (snitch, cva6, veer)
    run_impl.tcl            // synthesis, implementation, bitstream and reports
    filelists/gen_filelist.py // rtl filelist of a top, following its module/package references
    hw/cluster/tops/u55_snitch_top.sv                  // example top design, xdma to hbm working, no PU attached to hbm axi channel

## Usage

    1) from the repository root (Vivado 2024.2 in PATH):
        - make snitch | make cva | make veer    // project in build/<core>/u55_<core>.xpr
        - make bitgen [CORE=<core>] [JOBS=8]    // build/<core>/u55_<core>.bit, timing and utilization reports
      the project uses the rtl files listed in build/<core>/<core>.f, regenerated at each make

    2) manual flow (same steps of create_project.tcl):
        - create a new project with target alveo u55c accelerator
        - add the rtl sources and hw/cluster/xdma_boot/axi4_boot_check.v
        - tcl console: source gen_clock.tcl ; source qdma_interface.tcl
        - add xdc/u55/u55_snitch_const.xdc and generate the bitstream
    
    4) load mcs :
        - look in buil_mcs.tcl and replicate it, you must sobstitute all the paths, and specific numbers (ie board serial) in the file with yuor own before executing.
        - tcl_console:  build_mcs.tcl
    
    5) after flashing the mcs (may take 30mins/1h):
        - right click on fpga core in vivado hw manager -> reboot from mcs  
        - reboot the host which has the u55c board installed in his pcie slot

## Features:

    This design allows the user to:
    - Read and write from all the hbm memory from the host via xdma driver and the utilities in host_driver folder.
    - Send a active high reset signal out of hbm_interface to boot the attached system (master_reset).
    - The system target usage is to load a software payload in the hbm memory and make a processing node attached to S00 execute the payload.


## BD module inteface, EG for 1 channel exposed:

    hbm_interface i_hbm_interface (
    .HBM_REF_CLK_0_0    (HBM_REF_CLK),          // 100MHZ hbm clock
    .S00_AXI_0_araddr   ,   
    .S00_AXI_0_arburst  ,
    .S00_AXI_0_arcache  ,
    .S00_AXI_0_arid     ,
    .S00_AXI_0_arlen    ,
    .S00_AXI_0_arlock   ,
    .S00_AXI_0_arprot   ,
    .S00_AXI_0_arqos    ,
    .S00_AXI_0_arready  ,
    .S00_AXI_0_arsize   ,
    .S00_AXI_0_arvalid  ,
    .S00_AXI_0_awaddr   ,   
    .S00_AXI_0_awburst  ,
    .S00_AXI_0_awcache  ,
    .S00_AXI_0_awid     ,
    .S00_AXI_0_awlen    ,
    .S00_AXI_0_awlock   ,
    .S00_AXI_0_awprot   ,
    .S00_AXI_0_awqos    ,
    .S00_AXI_0_awready  ,
    .S00_AXI_0_awsize   ,
    .S00_AXI_0_awvalid  ,
    .S00_AXI_0_bid      ,
    .S00_AXI_0_bready   ,
    .S00_AXI_0_bresp    ,
    .S00_AXI_0_bvalid   ,
    .S00_AXI_0_rdata    ,
    .S00_AXI_0_rid      ,
    .S00_AXI_0_rlast    ,
    .S00_AXI_0_rready   ,
    .S00_AXI_0_rresp    ,
    .S00_AXI_0_rvalid   ,
    .S00_AXI_0_wdata    ,
    .S00_AXI_0_wlast    ,
    .S00_AXI_0_wready   ,
    .S00_AXI_0_wstrb    ,
    .S00_AXI_0_wvalid   ,
    .axi_clk_ariane_0   (clk),              // S00 axi clock
    .pcie_mgt_0_rxn     (pci_exp_rxn),      // pcie stuff
    .pcie_mgt_0_rxp     (pci_exp_rxp),
    .pcie_mgt_0_txn     (pci_exp_txn),
    .pcie_mgt_0_txp     (pci_exp_txp),
    .sys_clk_0          (sys_clk),
    .sys_clk_gt_0       (sys_clk_gt),
    .sys_rst_n_0        (sys_rst_n_c),
    .usr_irq_req_0      ('0),
    .master_areset_o_0(master_areset)      // master reset output
    );
    
See clocking setup example in top.sv