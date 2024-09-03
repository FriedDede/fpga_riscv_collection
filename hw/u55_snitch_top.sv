// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

// Description: Xilinx FPGA top-level
// Author: Florian Zaruba <zarubaf@iis.ee.ethz.ch>
`include "axi_typedef.svh"
`include "hbm_axi.svh"

module snitch_u55_xilinx_bd (
  input                 sys_clk_p       ,  // 100 MHz Clock for PCIe
  input                 sys_clk_n       ,  // 100 MHz Clock for PCIE
  input  logic          prst_n          , //reset
  input                 HBM_ref_clk_p   ,
  input                 HBM_ref_clk_n   ,
  output wire [7:0]     pci_exp_txp     ,
  output wire [7:0]     pci_exp_txn     ,
  input  wire [7:0]     pci_exp_rxp     ,
  input  wire [7:0]     pci_exp_rxn     ,
  input  logic          uart_rx         ,
  output logic          uart_tx
);

localparam BOOT_ADDR        = 32'h0000_0000;
localparam CORE_NUMBER      = 1;
localparam DRAM_CH_NUMBER   = CORE_NUMBER; // snitch clusters
localparam AxiAddrWidth     = snitch_cluster_pkg::AddrWidth;            // 64
localparam AxiDataWidth     = snitch_cluster_pkg::NarrowDataWidth;      // 64
localparam AxiIdWidthMaster = snitch_cluster_pkg::NarrowIdWidthIn;      // 4 
localparam AxiIdWidthSlaves = snitch_cluster_pkg::NarrowIdWidthIn + $clog2(3);  // 4 + 2 (each core exposes 3 channels)
localparam AxiUserWidth     = snitch_cluster_pkg::NarrowUserWidth;

// xbar config
localparam axi_pkg::xbar_cfg_t xbar_cfg = '{
NoSlvPorts:         3,
NoMstPorts:         2,
MaxMstTrans:        16,
MaxSlvTrans:        16,
FallThrough:        1'b0,
LatencyMode:        axi_pkg::CUT_ALL_AX,
PipelineStages:     1,
AxiIdWidthSlvPorts: AxiIdWidthMaster,
AxiIdUsedSlvPorts:  2,
UniqueIds:          '0,
AxiAddrWidth:       AxiAddrWidth,
AxiDataWidth:       AxiDataWidth,
NoAddrRules:        2
};
// generate the address map
typedef axi_pkg::xbar_rule_32_t  rule_t;
function rule_t [1:0] addr_map_gen ();
    // rom address 0x0 -> 0xffff
    addr_map_gen[0] = rule_t'{
    idx:        unsigned'(0),
    start_addr: 32'h0000_0000,
    end_addr:   32'h0000_ffff,
    default:    '0
    };
    // dram address 0x8000000 -> 0x8000000 + clog2(size)
    addr_map_gen[1] = rule_t'{
    idx:        unsigned'(1),
    start_addr: 32'h8000_0000,
    end_addr:   32'h8000_0000 + 32'h2000_0000, // 512MB dram
    default:    '0
    };
endfunction
localparam rule_t [1:0] AddrMap = addr_map_gen();

AXI_BUS #(
    .AXI_ADDR_WIDTH ( AxiAddrWidth     ),
    .AXI_DATA_WIDTH ( AxiDataWidth     ),
    .AXI_ID_WIDTH   ( AxiIdWidthSlaves ),
    .AXI_USER_WIDTH ( AxiUserWidth     )
) dram[DRAM_CH_NUMBER-1:0]();

// clocking and reset declaration
logic clk;

logic master_areset;
logic hbm_apb_areset_n;
logic core_areset_n;

// ---------------
// Core
// ---------------
    for ( genvar i=0; i<CORE_NUMBER; ++i) begin  : snitch_core_gen

        snitch_cluster_pkg::narrow_out_req_t    axi_icache_snitch_req;
        snitch_cluster_pkg::narrow_out_resp_t   axi_icache_snitch_resp;
        snitch_cluster_pkg::narrow_out_req_t    [1:0]axi_data_snitch_req;
        snitch_cluster_pkg::narrow_out_resp_t   [1:0]axi_data_snitch_resp;
        snitch_core_axi #(
            .AddrWidth          (AxiAddrWidth),
            .DataWidth          (AxiDataWidth),
            .IdWidthIn          (AxiIdWidthMaster),
            .BootAddr           (BOOT_ADDR),
            .SnitchPMACfg       (snitch_cluster_pkg::SnitchPMACfg)    
        ) i_snitch(
            .clk_i                  (clk),
            .rst_ni                 (core_areset_n),
            .hart_id_i              (i),
            // icache
            .inst_out_req_o         (axi_icache_snitch_req     ),
            .inst_out_resp_i        (axi_icache_snitch_resp    ),
            // integer core
            .data_core_out_req_o    (axi_data_snitch_req    [0]),
            .data_core_out_resp_i   (axi_data_snitch_resp   [0]),
            // fpu
            .data_fpu_out_req_o     (axi_data_snitch_req    [1]),
            .data_fpu_out_resp_i    (axi_data_snitch_resp   [1])
        );
        AXI_BUS #(
            .AXI_ADDR_WIDTH ( AxiAddrWidth     ),
            .AXI_DATA_WIDTH ( AxiDataWidth     ),
            .AXI_ID_WIDTH   ( AxiIdWidthMaster ),
            .AXI_USER_WIDTH ( AxiUserWidth     )
        ) axi_snitch2mux[2:0]();
        AXI_BUS #(
            .AXI_ADDR_WIDTH ( AxiAddrWidth     ),
            .AXI_DATA_WIDTH ( AxiDataWidth     ),
            .AXI_ID_WIDTH   ( AxiIdWidthSlaves ),
            .AXI_USER_WIDTH ( AxiUserWidth     )
        ) axi_xbar2mem();
        AXI_BUS #(
            .AXI_ADDR_WIDTH ( AxiAddrWidth     ),
            .AXI_DATA_WIDTH ( AxiDataWidth     ),
            .AXI_ID_WIDTH   ( AxiIdWidthSlaves ),
            .AXI_USER_WIDTH ( AxiUserWidth     )
        ) axi_xbar2clint();
        
        
        `AXI_ASSIGN_FROM_REQ (axi_snitch2mux[0], axi_data_snitch_req[0])
        `AXI_ASSIGN_TO_RESP  (axi_data_snitch_resp[0], axi_snitch2mux[0])
        `AXI_ASSIGN_FROM_REQ (axi_snitch2mux[1], axi_data_snitch_req[1])
        `AXI_ASSIGN_TO_RESP  (axi_data_snitch_resp[1], axi_snitch2mux[1])
        `AXI_ASSIGN_FROM_REQ (axi_snitch2mux[2], axi_icache_snitch_req)
        `AXI_ASSIGN_TO_RESP  (axi_icache_snitch_resp, axi_snitch2mux[2])
        axi_xbar_intf #(
            .AXI_USER_WIDTH(AxiUserWidth),
            .Cfg(xbar_cfg),
            .rule_t(rule_t)
        ) i_axi_xbar_intf (
            .clk_i(clk),
            .rst_ni(core_areset_n),
            .test_i('0),
            .slv_ports(axi_snitch2mux),
            .mst_ports({axi_xbar2mem,dram[i]}),
            .addr_map_i(AddrMap),
            .en_default_mst_port_i('0),
            .default_mst_port_i('0)
        );
// ----------------
// MEMORY SUBSYSTEM
// ----------------
    // ROM
        logic                    rom_req;
        logic [AxiAddrWidth-1:0] rom_addr;
        logic [AxiDataWidth-1:0] rom_rdata;
        logic                    rom_rvalid;
        axi_to_mem_intf #(
            .ADDR_WIDTH ( AxiAddrWidth),
            .DATA_WIDTH ( AxiDataWidth),
            .ID_WIDTH   ( AxiIdWidthSlaves),
            .USER_WIDTH ( AxiUserWidth),
            .NUM_BANKS  ( 1)
        ) i_axi_to_mem (
            .clk_i       ( clk),
            .rst_ni      ( core_areset_n),
            .busy_o      ( ),
            .slv         ( axi_xbar2mem),
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
        bootrom i_bootrom (
            .clk_i      ( clk       ),
            .req_i      ( rom_req   ),
            .addr_i     ( rom_addr  ),
            .rdata_o    ( rom_rdata ),
            .rvalid_o   ( rom_rvalid)
        );
    // HBM
        assign dram[i].b_user = '0;
        assign dram[i].r_user = '0;
    end


    // @ DRAM_BASE b1000_0000_0000_0000_0000_0000_0000_0000 [31:0]
    // HBM gets    b 000_0000_0000_0000_0000_0000_0000_0000 [30:0]
    // This allows us to have 31bit addressing (2GB)
    logic HBM_REF_CLK, hbm_apb_clk, sys_clk, sys_clk_gt, sys_rst_n_c;
    hbm_interface i_hbm_interface (
        .APB_0_PCLK_0       (hbm_apb_clk),
        .APB_0_PRESET_N_0   (hbm_apb_areset_n),
        .HBM_REF_CLK_0_0    (HBM_REF_CLK),
        .S00_AXI_0_araddr   (dram[0].ar_addr[30:0]),
        .S00_AXI_0_arburst  (dram[0].ar_burst),
        .S00_AXI_0_arcache  (dram[0].ar_cache),
        .S00_AXI_0_arid     (dram[0].ar_id),
        .S00_AXI_0_arlen    (dram[0].ar_len),
        .S00_AXI_0_arlock   (dram[0].ar_lock),
        .S00_AXI_0_arprot   (dram[0].ar_prot),
        .S00_AXI_0_arqos    (dram[0].ar_qos),
        .S00_AXI_0_arready  (dram[0].ar_ready),
        .S00_AXI_0_arsize   (dram[0].ar_size),
        .S00_AXI_0_arvalid  (dram[0].ar_valid),
        .S00_AXI_0_awaddr   (dram[0].aw_addr[30:0]),
        .S00_AXI_0_awburst  (dram[0].aw_burst),
        .S00_AXI_0_awcache  (dram[0].aw_cache),
        .S00_AXI_0_awid     (dram[0].aw_id),
        .S00_AXI_0_awlen    (dram[0].aw_len),
        .S00_AXI_0_awlock   (dram[0].aw_lock),
        .S00_AXI_0_awprot   (dram[0].aw_prot),
        .S00_AXI_0_awqos    (dram[0].aw_qos),
        .S00_AXI_0_awready  (dram[0].aw_ready),
        .S00_AXI_0_awsize   (dram[0].aw_size),
        .S00_AXI_0_awvalid  (dram[0].aw_valid),
        .S00_AXI_0_bid      (dram[0].b_id),
        .S00_AXI_0_bready   (dram[0].b_ready),
        .S00_AXI_0_bresp    (dram[0].b_resp),
        .S00_AXI_0_bvalid   (dram[0].b_valid),
        .S00_AXI_0_rdata    (dram[0].r_data),
        .S00_AXI_0_rid      (dram[0].r_id),
        .S00_AXI_0_rlast    (dram[0].r_last),
        .S00_AXI_0_rready   (dram[0].r_ready),
        .S00_AXI_0_rresp    (dram[0].r_resp),
        .S00_AXI_0_rvalid   (dram[0].r_valid),
        .S00_AXI_0_wdata    (dram[0].w_data),
        .S00_AXI_0_wlast    (dram[0].w_last),
        .S00_AXI_0_wready   (dram[0].w_ready),
        .S00_AXI_0_wstrb    (dram[0].w_strb),
        .S00_AXI_0_wvalid   (dram[0].w_valid),    
        .axi_clk_ariane_0   (clk),
        .pcie_mgt_0_rxn     (pci_exp_rxn),
        .pcie_mgt_0_rxp     (pci_exp_rxp),
        .pcie_mgt_0_txn     (pci_exp_txn),
        .pcie_mgt_0_txp     (pci_exp_txp),
        .sys_clk_0          (sys_clk),
        .sys_clk_gt_0       (sys_clk_gt),
        .sys_rst_n_0        (sys_rst_n_c),
        .usr_irq_req_0      ('0),
        .master_areset_o_0(master_areset)
    );

    // Must manually assign channels to each core dram bus
    //`AXI_ASSIGN_MASTER_TO_HBM_ARIANE(S00, dram[0])
    //`AXI_ASSIGN_MASTER_TO_HBM_ARIANE("S01", dram[1])
    //`AXI_ASSIGN_MASTER_TO_HBM_ARIANE("S02", dram[2])
    //`AXI_ASSIGN_MASTER_TO_HBM_ARIANE("S03", dram[3])
    // ... add other channels as needed

// -------------------------
// Clocking system and RESET
// -------------------------
    logic REF_CLK, pll_locked;
    IBUF sys_reset_n_ibuf (.O(sys_rst_n_c), .I(prst_n));

    IBUFDS hbm_ref_clk (
        .I(HBM_ref_clk_p), 
        .IB(HBM_ref_clk_n),
        .O(REF_CLK)
        );
    BUFG hbm_ref_clk_bufg (
        .I(REF_CLK), 
        .O(HBM_REF_CLK)
        );

    // we need to switch reset polarity for core reset
    logic clock_reset;
    assign clock_reset = ~sys_rst_n_c;

    xlnx_clk_gen_solo i_xlnx_clk_gen (
    .clk_out1 ( clk           ), // 50 MHz
    .clk_out2 ( hbm_apb_clk   ), // 100 MHz clock
    .clk_out3 (  ), // 250 Mhz pcie and hbm clk UNUSED
    .reset    ( clock_reset     ),
    .locked   ( pll_locked    ),
    .clk_in1  ( REF_CLK ) // 100 Mhz ref clk
    );

    IBUFDS_GTE4 #(
    .REFCLK_HROW_CK_SEL ( 2'b00 )
    ) IBUFDS_GTE4_inst (
    .O     ( sys_clk_gt ),
    .ODIV2 ( sys_clk    ),
    .CEB   ( 1'b0            ),
    .I     ( sys_clk_p       ),
    .IB    ( sys_clk_n       )
    );

    // core_areset_n is driven high when pll locks and the board releases his external reset
    // then the logic can be resetted from the hbm_xdma_interface
    rstgen i_rstgen_main (
        .clk_i        ( clk                      ),
        .rst_ni       ( pll_locked & (!master_areset) & sys_rst_n_c),
        .test_mode_i  ( '0                       ),
        .rst_no       ( core_areset_n            ),
        .init_no      (                          ) // keep open
    );

    proc_sys_reset_0 i_proc_sys_reset(
        .aux_reset_in(1'b1),
        .dcm_locked(1'b1),
        .mb_debug_sys_rst(1'b0),
        .slowest_sync_clk(hbm_apb_clk),
        .ext_reset_in(sys_rst_n_c),
        .peripheral_aresetn(hbm_apb_areset_n)
    );

// -----------------
// END
// -----------------

endmodule
