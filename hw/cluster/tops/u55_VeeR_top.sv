
// Copyright 2024 Politecnico di Milano.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

// Description: AMD u55c VeeR-EL2 hbm cluster top-level
// Author: Andrea Motta
//
// Requires the VeeR snapshot in build/<run>/veer_snapshot (VEER_CONFIG in the Makefile), its
// el2_param.vh, el2_pdef.vh and common_defines.vh must be in the include path.
// DCCM and I$ srams are instantiated in veer_fpga_mem as BRAM (ICCM disabled in the snapshot,
// veer_fpga_mem instantiates it too if enabled with -set=iccm_enable=1).
`include "axi_typedef.svh"
`include "hbm_axi.svh"

module veer_u55_xilinx_bd
    import el2_pkg::*;
    import axi_pkg::*;
#(
`include "el2_param.vh"
)
(
  input                 sys_clk_p       ,   // 100 MHz Clock for PCIE
  input                 sys_clk_n       ,   // 100 MHz Clock for PCIE
  input  logic          prst_n          ,   //reset
  input                 HBM_ref_clk_p   ,   // 100 MHz Clock for HBM
  input                 HBM_ref_clk_n   ,   // 100 MHz Clock for HBM
  output wire [15:0]    pcie_x16_txp     ,
  output wire [15:0]    pcie_x16_txn     ,
  input  wire [15:0]    pcie_x16_rxp     ,
  input  wire [15:0]    pcie_x16_rxn     ,
  input  logic          uart_rx         ,
  output logic          uart_tx
);

// design parameter
localparam BOOT_ADDR            = 32'h0000_0000;  // must match the snapshot reset_vec
localparam CORE_NUMBER          = 1;
localparam CLUSTER_NUMBER       = 1;
localparam TOTAL_CORE_NUMBER    = CORE_NUMBER * CLUSTER_NUMBER;
localparam PERIF_NUMBER         = 2;            // uart, timer (VeeR has its own PIC)
localparam DRAM_CH_NUMBER       = CLUSTER_NUMBER;
localparam VEER_AXI_PORTS       = 2;            // ifu + lsu, sb (debug) port is tied off

// axi paramenter
localparam AxiAddrWidth         = 32;           // VeeR is rv32
localparam AxiDataWidth         = 64;           // VeeR buses are 64 bit
localparam AxiPerifDataWidth    = 64;
localparam AxiIdWidthCore       = 4;            // >= max(pt.LSU_BUS_TAG, pt.IFU_BUS_TAG), 3 with the default snapshot
localparam AxiIdWidthToUncore   = AxiIdWidthCore + $clog2(VEER_AXI_PORTS * CORE_NUMBER);  // 5
localparam AxiIdWidthToPerifs   = AxiIdWidthToUncore + $clog2(CLUSTER_NUMBER);
localparam AxiUserWidth         = 1;

// xbar config
localparam axi_pkg::xbar_cfg_t xbar_cfg = '{
    NoSlvPorts:         VEER_AXI_PORTS * CORE_NUMBER,
    NoMstPorts:         5,          // bootrom + clint + dram + peripherals xbar + veer dma
    MaxMstTrans:        16,
    MaxSlvTrans:        16,
    FallThrough:        1'b0,
    LatencyMode:        axi_pkg::CUT_ALL_PORTS,
    PipelineStages:     1,
    AxiIdWidthSlvPorts: AxiIdWidthCore,
    AxiIdUsedSlvPorts:  AxiIdWidthCore,
    UniqueIds:          '0,
    AxiAddrWidth:       AxiAddrWidth,
    AxiDataWidth:       AxiDataWidth,
    NoAddrRules:        5           // bootrom + clint + dram + peripherals xbar + veer dma
};
// peripherals xbar setting
localparam axi_pkg::xbar_cfg_t perif_xbar_cfg = '{
    NoSlvPorts:         CLUSTER_NUMBER,
    NoMstPorts:         PERIF_NUMBER,
    MaxMstTrans:        16,
    MaxSlvTrans:        16,
    FallThrough:        1'b0,
    LatencyMode:        axi_pkg::CUT_ALL_PORTS,
    PipelineStages:     1,
    AxiIdWidthSlvPorts: AxiIdWidthToUncore,
    AxiIdUsedSlvPorts:  AxiIdWidthToUncore,
    UniqueIds:          '0,
    AxiAddrWidth:       AxiAddrWidth,
    AxiDataWidth:       AxiPerifDataWidth,
    NoAddrRules:        PERIF_NUMBER
};

// generate the address map
// VeeR internal regions (never seen on AXI): DCCM 0xF004_0000, PIC 0xF00C_0000
// the VeeR DMA port (DCCM, and ICCM if enabled: core load/store to the ICCM fault) is
// aliased at 0x6000_0000 - 0x7FFF_FFFF (addr | 0x8000_0000 on the DMA port)
typedef axi_pkg::xbar_rule_32_t  rule_t;
function rule_t [4:0] addr_map_gen ();
    // rom address 0x0 -> 0xffff
    addr_map_gen[0] = rule_t'{
        idx:        unsigned'(0),
        start_addr: 32'h0000_0000,
        end_addr:   32'h0001_0000,
        default:    '0
    };
    // dram address 0x8000000 -> 0x8000000 + clog2(size)
    addr_map_gen[1] = rule_t'{
        idx:        unsigned'(1),
        start_addr: 32'h8000_0000,
        end_addr:   32'h8000_0000 + 32'h2000_0000, // 512MB per cluster here
        default:    '0
    };
    // Perif (UART TIMER ... )
    addr_map_gen[2] = rule_t'{
        idx:        unsigned'(2),
        start_addr: 32'h1000_0000,
        end_addr:   32'h6000_0000,
        default:    '0
    };
    // VeeR DMA port: DCCM @ 0x7004_0000 (ICCM @ 0x6E00_0000 if enabled)
    addr_map_gen[4] = rule_t'{
        idx:        unsigned'(4),
        start_addr: 32'h6000_0000,
        end_addr:   32'h8000_0000,
        default:    '0
    };
    // CLINT (Pulp Specs RISC-V privilege spec 1.11 compatible CLINT )
    addr_map_gen[3] = rule_t'{
        idx:        unsigned'(3),
        start_addr: 32'h0200_0000,
        end_addr:   32'h0200_C000,
        default:    '0
    };
endfunction

function rule_t [PERIF_NUMBER - 1 : 0] addr_map_perif_gen ();
    // Uart
    addr_map_perif_gen[0] = rule_t'{
        idx:        unsigned'(0),
        start_addr: 32'h1400_0000,
        end_addr:   32'h1400_1000,
        default:    '0
    };
    // Timer
    addr_map_perif_gen[1] = rule_t'{
        idx:        unsigned'(1),
        start_addr: 32'h1400_1000,
        end_addr:   32'h1400_2000,
        default:    '0
    };

endfunction

localparam rule_t [4:0] AddrMapUncore = addr_map_gen();
localparam rule_t [PERIF_NUMBER - 1 : 0] AddrMapPerif = addr_map_perif_gen();
AXI_BUS #(
    .AXI_ADDR_WIDTH ( AxiAddrWidth     ),
    .AXI_DATA_WIDTH ( AxiDataWidth     ),
    .AXI_ID_WIDTH   ( AxiIdWidthToUncore ),
    .AXI_USER_WIDTH ( AxiUserWidth     )
) axi_dram[DRAM_CH_NUMBER-1:0]();
AXI_BUS #(
    .AXI_ADDR_WIDTH ( AxiAddrWidth       ),
    .AXI_DATA_WIDTH ( AxiPerifDataWidth  ),
    .AXI_ID_WIDTH   ( AxiIdWidthToUncore ),
    .AXI_USER_WIDTH ( AxiUserWidth       )
) axi_uncore2pxbar[CLUSTER_NUMBER-1:0]();
AXI_BUS #(
    .AXI_ADDR_WIDTH ( AxiAddrWidth       ),
    .AXI_DATA_WIDTH ( AxiPerifDataWidth  ),
    .AXI_ID_WIDTH   ( AxiIdWidthToPerifs ),
    .AXI_USER_WIDTH ( AxiUserWidth       )
) axi_peripherals[PERIF_NUMBER - 1:0]();

// interrupt handling bus
// uart and timer irqs go straight into the VeeR internal PIC (extintsrc_req)
localparam int EXT_TIMERS = 2; // 2 timers per core
logic [(EXT_TIMERS *2) - 1 : 0] ext_timer_irq;
logic uart_irq;

// clocking and reset declaration: core, cluster (crossbar) and peripheral domains,
// the core resets are generated inside the <core>_cd_wrapper
// each cluster has its own clock generator (cluster and core clocks), peripherals have one
logic [CLUSTER_NUMBER-1:0][CORE_NUMBER-1:0] clk_core;
logic [CLUSTER_NUMBER-1:0]                  clk_cluster, rst_cluster_n, cluster_locked;
logic                                       clk_periph, rst_periph_n;
logic                                       SOC_REF_CLK, clock_reset;
(* keep = "true" *) logic soc_rst_async_n;
logic master_areset;
// ---------------
// Core
// ---------------

    for ( genvar i=0; i<CLUSTER_NUMBER; ++i) begin  : cluster_gen

        // cluster clock generator: crossbar clock and one clock per core
        cluster_clk_gen #(
            .NumCores      ( CORE_NUMBER       )
        ) i_cluster_clk_gen (
            .clk_in1       ( SOC_REF_CLK       ), // 100 Mhz ref clk
            .reset         ( clock_reset       ),
            .locked        ( cluster_locked[i] ),
            .clk_cluster_o ( clk_cluster[i]    ),
            .clk_core_o    ( clk_core[i]       )
        );
        rstgen i_rstgen_cluster (
            .clk_i        ( clk_cluster[i]     ),
            .rst_ni       ( soc_rst_async_n    ),
            .test_mode_i  ( '0                 ),
            .rst_no       ( rst_cluster_n[i]   ),
            .init_no      (                    ) // keep open
        );

        logic [CORE_NUMBER -1 : 0]timer_irq;
        logic [CORE_NUMBER -1 : 0]ipi;
        AXI_BUS #(
            .AXI_ADDR_WIDTH ( AxiAddrWidth     ),
            .AXI_DATA_WIDTH ( AxiDataWidth     ),
            .AXI_ID_WIDTH   ( AxiIdWidthCore   ),
            .AXI_USER_WIDTH ( AxiUserWidth     )
        ) axi_veer2xbar[VEER_AXI_PORTS * CORE_NUMBER - 1 : 0]();
        AXI_BUS #(
           .AXI_ADDR_WIDTH ( AxiAddrWidth     ),
           .AXI_DATA_WIDTH ( AxiDataWidth     ),
           .AXI_ID_WIDTH   ( AxiIdWidthToUncore),
           .AXI_USER_WIDTH ( AxiUserWidth     )
         ) axi_xbar2uncore[4:0]();

        for ( genvar j=0; j<CORE_NUMBER; ++j) begin  : core_gen
            // DMA slave port (DCCM/ICCM access): the dma window of the cluster goes to core 0
            AXI_BUS #(
                .AXI_ADDR_WIDTH ( AxiAddrWidth     ),
                .AXI_DATA_WIDTH ( AxiDataWidth     ),
                .AXI_ID_WIDTH   ( AxiIdWidthToUncore),
                .AXI_USER_WIDTH ( AxiUserWidth     )
            ) axi_dma();
            if (j == 0) begin : gen_dma
                `AXI_ASSIGN(axi_dma, axi_xbar2uncore[4])
            end else begin : gen_no_dma
                assign axi_dma.aw_valid = 1'b0;
                assign axi_dma.w_valid  = 1'b0;
                assign axi_dma.b_ready  = 1'b1;
                assign axi_dma.ar_valid = 1'b0;
                assign axi_dma.r_ready  = 1'b1;
            end

            // core in its clock domain, AXI ports in the cluster domain
            // core interrupts: PIC source 1 = uart, 2..5 = ext timers
            veer_cd_wrapper #(
                .pt             ( pt                 ),
                .AxiAddrWidth   ( AxiAddrWidth       ),
                .AxiDataWidth   ( AxiDataWidth       ),
                .AxiUserWidth   ( AxiUserWidth       ),
                .AxiIdWidth     ( AxiIdWidthCore     ),
                .AxiDmaIdWidth  ( AxiIdWidthToUncore ),
                .BootAddr       ( BOOT_ADDR          ),
                .CoreId         ( j                  )   // enumeration restarts in each cluster
            ) i_veer (
                .clk_core_i     ( clk_core[i][j]           ),
                .clk_cluster_i  ( clk_cluster[i]        ),
                .rst_cluster_ni ( rst_cluster_n[i]      ),
                .rst_ni         ( soc_rst_async_n    ),
                .timer_irq_i    ( timer_irq[j]       ),
                .soft_irq_i     ( ipi[j]             ),
                .ext_irq_i      ( pt.PIC_TOTAL_INT'({ext_timer_irq, uart_irq}) ),
                .ifu            ( axi_veer2xbar[VEER_AXI_PORTS * j]     ),
                .lsu            ( axi_veer2xbar[VEER_AXI_PORTS * j + 1] ),
                .dma            ( axi_dma            )
            );

        end : core_gen

        AXI_BUS #(
            .AXI_ADDR_WIDTH ( AxiAddrWidth     ),
            .AXI_DATA_WIDTH ( AxiPerifDataWidth     ),
            .AXI_ID_WIDTH   ( AxiIdWidthToUncore ),
            .AXI_USER_WIDTH ( AxiUserWidth     )
        ) axi_rom();
        AXI_BUS #(
            .AXI_ADDR_WIDTH ( AxiAddrWidth     ),
            .AXI_DATA_WIDTH ( AxiPerifDataWidth     ),
            .AXI_ID_WIDTH   ( AxiIdWidthToUncore ),
            .AXI_USER_WIDTH ( AxiUserWidth     )
        ) axi_clint();

        axi_xbar_intf #(
            .AXI_USER_WIDTH(AxiUserWidth),
            .Cfg(xbar_cfg),
            .rule_t(rule_t)
        ) i_axi_xbar_intf (
            .clk_i(clk_cluster[i]),
            .rst_ni(rst_cluster_n[i]),
            .test_i('0),
            .slv_ports(axi_veer2xbar),
            .mst_ports(axi_xbar2uncore),
            .addr_map_i(AddrMapUncore),
            .en_default_mst_port_i('0),
            .default_mst_port_i('0)
        );

        // To external peripherals, cluster -> peripheral clock domain
            axi_cdc_intf #(
                .AXI_ID_WIDTH   ( AxiIdWidthToUncore ),
                .AXI_ADDR_WIDTH ( AxiAddrWidth       ),
                .AXI_DATA_WIDTH ( AxiPerifDataWidth ),
                .AXI_USER_WIDTH ( AxiUserWidth       ),
                .LOG_DEPTH      ( 2                  )
            ) i_cdc_perif (
                .src_clk_i  ( clk_cluster[i]         ),
                .src_rst_ni ( rst_cluster_n[i]       ),
                .src        ( axi_xbar2uncore[2]  ),
                .dst_clk_i  ( clk_periph          ),
                .dst_rst_ni ( rst_periph_n        ),
                .dst        ( axi_uncore2pxbar[i] )
            );


        // CLINT

            `AXI_ASSIGN(axi_clint ,axi_xbar2uncore[3])


            logic rtc;
            always_ff @(posedge clk_cluster[i] or negedge rst_cluster_n[i]) begin
                if (~rst_cluster_n[i]) begin
                    rtc <= 0;
                end else begin
                    rtc <= rtc ^ 1'b1;
                end
            end
            axi_clint #(
                .AddrWidth(AxiAddrWidth),
                .DataWidth(AxiPerifDataWidth),
                .IdWidthIn(AxiIdWidthToUncore),
                .UserWidth(AxiUserWidth),
                .NR_CORES(CORE_NUMBER)
            ) axi_clint_instance(
                .clk_i(clk_cluster[i]),
                .rst_ni(rst_cluster_n[i]),
                .testmode_i('0),
                .clint(axi_clint),
                .rtc_i(rtc),
                .timer_irq_o(timer_irq),
                .ipi_o(ipi)
            );

        // ROM

            `AXI_ASSIGN(axi_rom ,axi_xbar2uncore[0])

            logic                           rom_req;
            logic [AxiAddrWidth-1:0]        rom_addr;
            logic [AxiPerifDataWidth-1:0]   rom_rdata;
            logic                           rom_rvalid;
            axi_to_mem_intf #(
                .ADDR_WIDTH ( AxiAddrWidth),
                .DATA_WIDTH ( AxiPerifDataWidth),
                .ID_WIDTH   ( AxiIdWidthToUncore),
                .USER_WIDTH ( AxiUserWidth),
                .NUM_BANKS  ( 1)
            ) i_axi_to_mem (
                .clk_i       (clk_cluster[i]),
                .rst_ni      (rst_cluster_n[i]),
                .busy_o      ( ),
                .slv         ( axi_rom),
                .mem_req_o   ( rom_req),
                .mem_gnt_i   ( '1),
                .mem_addr_o  ( rom_addr),
                .mem_wdata_o ( ),
                .mem_strb_o  ( ),
                .mem_atop_o  ( ),
                .mem_we_o    ( ),
                .mem_rvalid_i( rom_rvalid),
                .mem_rdata_i ( rom_rdata)
            );
            // rv32imc build of bootrom_u55 (make -C bootrom_u55 CORE=veer)
            bootrom_veer i_bootrom (
                .clk_i      (clk_cluster[i]),
                .req_i      ( rom_req   ),
                .addr_i     ( rom_addr  ),
                .rdata_o    ( rom_rdata ),
                .rvalid_o   ( rom_rvalid)
            );

        // DRAM
        `AXI_ASSIGN(axi_dram[i],axi_xbar2uncore[1])
        // tie unused signal in bram channel to 0
        assign axi_dram[i].b_user = '0;
        assign axi_dram[i].r_user = '0;
    end : cluster_gen

// -----------------------
// MEMORY SUBSYSTEM
// -----------------------

    // @ DRAM_BASE b1000_0000_0000_0000_0000_0000_0000_0000 [31:0]
    // HBM gets    b 000_0000_0000_0000_0000_0000_0000_0000 [30:0]
    // This allows us to have 31bit addressing (2GB)
    // For more clusters, connect S01..S0N as in u55_cva6_top.sv
    logic HBM_REF_CLK, sys_clk, sys_clk_gt, sys_rst_n_c;
   hbm_interface i_hbm_interface (
        .HBM_REF_CLK_0_0    (HBM_REF_CLK),
        // one channel per cluster: add `HBM_ASSIGN_CHANNEL(S0<i>, axi_dram[<i>], <i>, clk_cluster[<i>])
        // for more clusters and remove the corresponding tie off
        `HBM_ASSIGN_CHANNEL(S00, axi_dram[0], 0, clk_cluster[0]),
        `HBM_TIE_OFF_CHANNEL(S01, clk_cluster[0]),
        `HBM_TIE_OFF_CHANNEL(S02, clk_cluster[0]),
        `HBM_TIE_OFF_CHANNEL(S03, clk_cluster[0]),
        `HBM_TIE_OFF_CHANNEL(S04, clk_cluster[0]),
        `HBM_TIE_OFF_CHANNEL(S05, clk_cluster[0]),
        `HBM_TIE_OFF_CHANNEL(S06, clk_cluster[0]),
        `HBM_TIE_OFF_CHANNEL(S07, clk_cluster[0]),
        `HBM_TIE_OFF_CHANNEL(S08, clk_cluster[0]),
        `HBM_TIE_OFF_CHANNEL(S09, clk_cluster[0]),
        `HBM_TIE_OFF_CHANNEL(S10, clk_cluster[0]),
        `HBM_TIE_OFF_CHANNEL(S11, clk_cluster[0]),
        .pcie_mgt_0_rxn     (pcie_x16_rxn),
        .pcie_mgt_0_rxp     (pcie_x16_rxp),
        .pcie_mgt_0_txn     (pcie_x16_txn),
        .pcie_mgt_0_txp     (pcie_x16_txp),
        .sys_clk_0          (sys_clk),
        .sys_clk_gt_0       (sys_clk_gt),
        .sys_rst_n_0        (sys_rst_n_c),
        .usr_irq_req_0      ('0),
        .master_areset_o_0  (master_areset)
    );

// -----------------------
// PERYPHERALS SUBSYSTEM
// -----------------------
    axi_xbar_intf #(
        .AXI_USER_WIDTH(AxiUserWidth),
        .Cfg(perif_xbar_cfg),
        .rule_t(rule_t)
    ) i_axi_xbar_intf_perif (
        .clk_i(clk_periph),
        .rst_ni(rst_periph_n),
        .test_i('0),
        .slv_ports(axi_uncore2pxbar),
        .mst_ports(axi_peripherals),
        .addr_map_i(AddrMapPerif),
        .en_default_mst_port_i('0),
        .default_mst_port_i('0)
    );
    axi_uart #(
        .AxiAddrWidth(AxiAddrWidth),
        .AxiDataWidth(AxiPerifDataWidth),
        .AxiIdWidth(AxiIdWidthToPerifs),
        .AxiUserWidth(AxiUserWidth)
    ) axi_uart_instance(
        .clk_i(clk_periph),
        .rst_ni(rst_periph_n),
        .uart(axi_peripherals[0]),
        .uart_irq(uart_irq),
        .tx_o(uart_tx),
        .rx_i(uart_rx)
    );
    axi_timer #(
        .AxiAddrWidth(AxiAddrWidth),
        .AxiDataWidth(AxiPerifDataWidth),
        .AxiIdWidth(AxiIdWidthToPerifs),
        .AxiUserWidth(AxiUserWidth),
        .TimerCount(EXT_TIMERS)
    ) axi_timer_instance(
        .clk_i(clk_periph),
        .rst_ni(rst_periph_n),
        .timer(axi_peripherals[1]),
        .timer_irq(ext_timer_irq)
    );

// -------------------------
// Clocking system and RESET
// -------------------------
    logic REF_CLK, pll_locked;
    IBUF    sys_reset_n_ibuf (
        .O(sys_rst_n_c),
        .I(prst_n)
    );
    IBUFDS  hbm_ref_clk_ibuf (
        .I(HBM_ref_clk_p),
        .IB(HBM_ref_clk_n),
        .O(REF_CLK)
    );
    BUFG    hbm_ref_clk_bufg (
        .I(REF_CLK),
        .O(HBM_REF_CLK)
    );
    BUFG    soc_ref_clk_bufg (
        .I(REF_CLK),
        .O(SOC_REF_CLK)
    );

    // we need to switch reset polarity for core reset
    assign clock_reset = ~sys_rst_n_c;

    // peripheral clock, the clusters have their own clock generator (cluster_clk_gen):
    // make FREQ_CORE=<MHz> FREQ_CLUSTER=<MHz> FREQ_PERIPH=<MHz> (default 50)
    logic periph_locked;
    xlnx_clk_gen_periph i_clk_gen_periph (
    .periph_clk  ( clk_periph      ),
    .reset       ( clock_reset     ),
    .locked      ( periph_locked   ),
    .clk_in1     ( SOC_REF_CLK     ) // 100 Mhz ref clk
    );
    assign pll_locked = periph_locked & (&cluster_locked);

    IBUFDS_GTE4 #(
    .REFCLK_HROW_CK_SEL ( 2'b00 )
    ) IBUFDS_GTE4_inst (
    .O     ( sys_clk_gt ),
    .ODIV2 ( sys_clk    ),
    .CEB   ( 1'b0            ),
    .I     ( sys_clk_p       ),
    .IB    ( sys_clk_n       )
    );

    // the logic is in reset until the pll locks and the board releases his external reset,
    // then it can be resetted from the hbm_xdma_interface (master_areset).
    // The reset is asserted asynchronously and released by a rstgen in each clock domain
    assign soc_rst_async_n = pll_locked & ~master_areset & sys_rst_n_c;
    rstgen i_rstgen_periph (
        .clk_i        ( clk_periph               ),
        .rst_ni       ( soc_rst_async_n          ),
        .test_mode_i  ( '0                       ),
        .rst_no       ( rst_periph_n             ),
        .init_no      (                          ) // keep open
    );

// -----------------
// END
// -----------------

endmodule
