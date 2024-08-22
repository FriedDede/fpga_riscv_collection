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

module ariane_u55_xilinx_bd (
  input                sys_clk_p       ,  // 100 MHz Clock for PCIe
  input                sys_clk_n       ,  // 100 MHz Clock for PCIE
  input  logic         prst_n          , //reset
  input                HBM_ref_clk_p   ,
  input                HBM_ref_clk_n   ,
  output wire [7:0]    pci_exp_txp     ,
  output wire [7:0]    pci_exp_txn     ,
  input  wire [7:0]    pci_exp_rxp     ,
  input  wire [7:0]    pci_exp_rxn     ,
  input  logic        uart_rx     ,
  output logic        uart_tx
);

localparam CORE_NUMBER = 1;
localparam NBSlave = 1 + CORE_NUMBER; // debug, ariane
localparam AxiAddrWidth = 64;
localparam AxiDataWidth = 64;
localparam AxiIdWidthMaster = 4;
localparam AxiIdWidthSlaves = AxiIdWidthMaster + $clog2(NBSlave); // 5
localparam AxiUserWidth = 1;

AXI_BUS #(
    .AXI_ADDR_WIDTH ( AxiAddrWidth     ),
    .AXI_DATA_WIDTH ( AxiDataWidth     ),
    .AXI_ID_WIDTH   ( AxiIdWidthMaster ),
    .AXI_USER_WIDTH ( AxiUserWidth     )
) slave[NBSlave-1:0]();

AXI_BUS #(
    .AXI_ADDR_WIDTH ( AxiAddrWidth     ),
    .AXI_DATA_WIDTH ( AxiDataWidth     ),
    .AXI_ID_WIDTH   ( AxiIdWidthSlaves ),
    .AXI_USER_WIDTH ( AxiUserWidth     )
) master[ariane_soc::NB_PERIPHERALS-1:0]();

logic ndmreset;
logic ndmreset_n;
logic debug_req_irq;
logic time_irq;
logic ipi;

// ROM
logic                    rom_req;
logic [AxiAddrWidth-1:0] rom_addr;
logic [AxiDataWidth-1:0] rom_rdata;

// Debug
logic          debug_req_valid;
logic          debug_req_ready;
dm::dmi_req_t  debug_req;
logic          debug_resp_valid;
logic          debug_resp_ready;
dm::dmi_resp_t debug_resp;

// IRQ
logic [1:0] irq;
assign test_en    = 1'b0;

// AXI protocol checker
logic [NBSlave-1:0] pc_asserted;
logic [159:0]   pc_status;

// ---------------
// AXI Xbar
// ---------------
axi_node_wrap_with_slices #(
    // three ports from Ariane (instruction, data and bypass)
    .NB_SLAVE           ( NBSlave                    ),
    .NB_MASTER          ( ariane_soc::NB_PERIPHERALS ),
    .NB_REGION          ( ariane_soc::NrRegion       ),
    .AXI_ADDR_WIDTH     ( AxiAddrWidth               ),
    .AXI_DATA_WIDTH     ( AxiDataWidth               ),
    .AXI_USER_WIDTH     ( AxiUserWidth               ),
    .AXI_ID_WIDTH       ( AxiIdWidthMaster           ),
    .MASTER_SLICE_DEPTH ( 2                          ),
    .SLAVE_SLICE_DEPTH  ( 2                          )
) i_axi_xbar (
    .clk          ( clk        ),
    .rst_n        ( ndmreset_n ),
    .test_en_i    ( test_en    ),
    .slave        ( slave      ),
    .master       ( master     ),
    .start_addr_i ({
        ariane_soc::DebugBase,
        ariane_soc::ROMBase,
        ariane_soc::CLINTBase, 
        ariane_soc::PLICBase,
        ariane_soc::UARTBase,
        ariane_soc::TimerBase,
        ariane_soc::SPIBase,
        ariane_soc::EthernetBase,
        ariane_soc::GPIOBase,
        ariane_soc::DRAMBase
    }),
    .end_addr_i   ({
        ariane_soc::DebugBase    + ariane_soc::DebugLength - 1,
        ariane_soc::ROMBase      + ariane_soc::ROMLength - 1,
        ariane_soc::CLINTBase    + ariane_soc::CLINTLength - 1,
        ariane_soc::PLICBase     + ariane_soc::PLICLength - 1,
        ariane_soc::UARTBase     + ariane_soc::UARTLength - 1,
        ariane_soc::TimerBase    + ariane_soc::TimerLength - 1,
        ariane_soc::SPIBase      + ariane_soc::SPILength - 1,
        ariane_soc::EthernetBase + ariane_soc::EthernetLength -1,
        ariane_soc::GPIOBase     + ariane_soc::GPIOLength - 1,
        ariane_soc::DRAMBase     + ariane_soc::DRAMLength - 1
    }),
    .valid_rule_i (ariane_soc::ValidRule)
);

// ---------------
// Core
// ---------------
    snitch_cluster_pkg::wide_out_req_t  [CORE_NUMBER-1 : 0]   axi_icache_snitch_req;
    snitch_cluster_pkg::wide_out_resp_t [CORE_NUMBER-1 : 0]    axi_icache_snitch_resp;
    snitch_cluster_pkg::narrow_out_req_t  [CORE_NUMBER-1 : 0]  axi_data_snitch_req;
    snitch_cluster_pkg::narrow_out_resp_t [CORE_NUMBER-1 : 0]  axi_data_snitch_resp;
genvar i;
generate;
    for ( i=0; i<CORE_NUMBER; ++i) 
    begin

        snitch_cluster_wrapper #() i_snitch(
            .clk_i              (clk),
            .rst_ni             (ndmreset_n),
            .debug_req_i        ('0),
            .meip_i             (irq),
            .mtip_i             (time_irq),
            .msip_i             (ipi),
            .hart_base_id_i     ('0),
            .cluster_base_addr_i('0),
            .narrow_out_req_o   (axi_data_snitch_req[i]),                  // data narrows access
            .narrow_out_resp_i  (axi_data_snitch_resp[i]),
            .wide_out_req_o     (axi_icache_snitch_req[i]),                 // instruction dma access
            .wide_out_resp_i    (axi_icache_snitch_resp[i])
        );
        AXI_BUS #(
            .AXI_ADDR_WIDTH ( AxiAddrWidth     ),
            .AXI_DATA_WIDTH ( AxiDataWidth     ),
            .AXI_ID_WIDTH   ( AxiIdWidthMaster ),
            .AXI_USER_WIDTH ( AxiUserWidth     )
        ) snitch_mst[1:0]();
                    
        `AXI_ASSIGN_MASTER_TO_ARIANE_AXI_INT(snitch_mst[0],axi_data_snitch_req[i],axi_data_snitch_resp[i])
        `AXI_ASSIGN_MASTER_TO_ARIANE_AXI_INT(snitch_mst[1],axi_icache_snitch_req[i],axi_icache_snitch_resp[i])
        
        axi_mux_intf #(
            .NO_SLV_PORTS (2)
        ) i_mux (
            .clk_i (clk),
            .rst_ni (ndmreset_n),
            .test_i (0),
            .slv (snitch_mst),
            .mst (slave[i])
        );  
    end
endgenerate


// ---------------
// CLINT
// ---------------
// divide clock by two
always_ff @(posedge clk or negedge ndmreset_n) begin
  if (~ndmreset_n) begin
    rtc <= 0;
  end else begin
    rtc <= rtc ^ 1'b1;
  end
end

ariane_axi::req_t    axi_clint_req;
ariane_axi::resp_t   axi_clint_resp;

clint #(
    .AXI_ADDR_WIDTH ( AxiAddrWidth     ),
    .AXI_DATA_WIDTH ( AxiDataWidth     ),
    .AXI_ID_WIDTH   ( AxiIdWidthSlaves ),
    .NR_CORES       ( 1                )
) i_clint (
    .clk_i       ( clk            ),
    .rst_ni      ( ndmreset_n     ),
    .testmode_i  ( test_en        ),
    .axi_req_i   ( axi_clint_req  ),
    .axi_resp_o  ( axi_clint_resp ),
    .rtc_i       ( rtc            ),
    .timer_irq_o ( timer_irq      ),
    .ipi_o       ( ipi            )
);

axi_slave_connect i_axi_slave_connect_clint (.axi_req_o(axi_clint_req), .axi_resp_i(axi_clint_resp), .slave(master[ariane_soc::CLINT]));

// ---------------
// ROM
// ---------------
axi2mem #(
    .AXI_ID_WIDTH   ( AxiIdWidthSlaves ),
    .AXI_ADDR_WIDTH ( AxiAddrWidth     ),
    .AXI_DATA_WIDTH ( AxiDataWidth     ),
    .AXI_USER_WIDTH ( AxiUserWidth     )
) i_axi2rom (
    .clk_i  ( clk                     ),
    .rst_ni ( ndmreset_n              ),
    .slave  ( master[ariane_soc::ROM] ),
    .req_o  ( rom_req                 ),
    .we_o   (                         ),
    .addr_o ( rom_addr                ),
    .be_o   (                         ),
    .data_o (                         ),
    .data_i ( rom_rdata               )
);

bootrom i_bootrom (
    .clk_i   ( clk       ),
    .req_i   ( rom_req   ),
    .addr_i  ( rom_addr  ),
    .rdata_o ( rom_rdata )
);
// ---------------
// Peripherals
// ---------------
ariane_peripherals #(
    .AxiAddrWidth ( AxiAddrWidth     ),
    .AxiDataWidth ( AxiDataWidth     ),
    .AxiIdWidth   ( AxiIdWidthSlaves ),
    .AxiUserWidth ( AxiUserWidth     ),
    .InclUART     ( 1'b1             ),
    .InclGPIO     ( 1'b0             ),
    .InclSPI      ( 1'b0             ),
    .InclEthernet ( 1'b0             )
) i_ariane_peripherals (
    .clk_i        ( clk                          ),
    .clk_200MHz_i (                              ), // eth clock
    .rst_ni       ( ndmreset_n                   ),
    .plic         ( master[ariane_soc::PLIC]     ),
    .uart         ( master[ariane_soc::UART]     ),
    .spi          ( master[ariane_soc::SPI]      ),
    .gpio         ( master[ariane_soc::GPIO]     ),
    .ethernet     ( master[ariane_soc::Ethernet] ),
    .timer        ( master[ariane_soc::Timer]    ),
    .irq_o        ( irq                          ),
    .rx_i         ( uart_rx                      ),
    .tx_o         ( uart_tx                      ),
    .eth_clk_i     (),
    .eth_rxck      (),
    .eth_rxctl     (),
    .eth_rxd       (),
    .eth_txck      (),
    .eth_txctl     (),
    .eth_txd       (),
    .eth_rst_n     (),
    .phy_tx_clk_i  (),
    .eth_mdio      (),
    .eth_mdc       (),
    .spi_clk_o     (),
    .spi_mosi      (),
    .spi_miso      (),
    .spi_ss        (),
    .sd_clk_i      (),
    .leds_o        (),
    .dip_switches_i()
);
// ---------------
// HBM
// ---------------
    AXI_BUS #(
        .AXI_ADDR_WIDTH ( AxiAddrWidth     ),
        .AXI_DATA_WIDTH ( AxiDataWidth     ),
        .AXI_ID_WIDTH   ( AxiIdWidthSlaves ),
        .AXI_USER_WIDTH ( AxiUserWidth     )
    ) dram();

    axi_riscv_atomics_wrap #(
        .AXI_ADDR_WIDTH ( AxiAddrWidth     ),
        .AXI_DATA_WIDTH ( AxiDataWidth     ),
        .AXI_ID_WIDTH   ( AxiIdWidthSlaves ),
        .AXI_USER_WIDTH ( AxiUserWidth     ),
        .AXI_MAX_WRITE_TXNS ( 1  ),
        .RISCV_WORD_WIDTH   ( 64 )
    ) i_axi_riscv_atomics (
        .clk_i  ( clk                      ),
        .rst_ni ( ndmreset_n               ),
        .slv    ( master[ariane_soc::DRAM] ),
        .mst    ( dram                     )
    );

    assign dram.r_user = '0;
    assign dram.b_user = '0;

    // @ DRAM_BASE b1000_0000_0000_0000_0000_0000_0000_0000 [31:0]
    // HBM gets    b 000_0000_0000_0000_0000_0000_0000_0000 [30:0]
    // This allows us to have 31bit addressing (2GB)
    hbm_interface i_hbm_interface (
        .APB_0_PCLK_0       (hbm_apb_clk),
        .APB_0_PRESET_N_0   (hbm_apb_areset_n),
        .HBM_REF_CLK_0_0    (HBM_REF_CLK),
        .S00_AXI_0_araddr   (dram.ar_addr[30:0]),
        .S00_AXI_0_arburst  (dram.ar_burst),
        .S00_AXI_0_arcache  (dram.ar_cache),
        .S00_AXI_0_arid     (dram.ar_id),
        .S00_AXI_0_arlen    (dram.ar_len),
        .S00_AXI_0_arlock   (dram.ar_lock),
        .S00_AXI_0_arprot   (dram.ar_prot),
        .S00_AXI_0_arqos    (dram.ar_qos),
        .S00_AXI_0_arready  (dram.ar_ready),
        .S00_AXI_0_arsize   (dram.ar_size),
        .S00_AXI_0_arvalid  (dram.ar_valid),
        .S00_AXI_0_awaddr   (dram.aw_addr[30:0]),
        .S00_AXI_0_awburst  (dram.aw_burst),
        .S00_AXI_0_awcache  (dram.aw_cache),
        .S00_AXI_0_awid     (dram.aw_id),
        .S00_AXI_0_awlen    (dram.aw_len),
        .S00_AXI_0_awlock   (dram.aw_lock),
        .S00_AXI_0_awprot   (dram.aw_prot),
        .S00_AXI_0_awqos    (dram.aw_qos),
        .S00_AXI_0_awready  (dram.aw_ready),
        .S00_AXI_0_awsize   (dram.aw_size),
        .S00_AXI_0_awvalid  (dram.aw_valid),
        .S00_AXI_0_bid      (dram.b_id),
        .S00_AXI_0_bready   (dram.b_ready),
        .S00_AXI_0_bresp    (dram.b_resp),
        .S00_AXI_0_bvalid   (dram.b_valid),
        .S00_AXI_0_rdata    (dram.r_data),
        .S00_AXI_0_rid      (dram.r_id),
        .S00_AXI_0_rlast    (dram.r_last),
        .S00_AXI_0_rready   (dram.r_ready),
        .S00_AXI_0_rresp    (dram.r_resp),
        .S00_AXI_0_rvalid   (dram.r_valid),
        .S00_AXI_0_wdata    (dram.w_data),
        .S00_AXI_0_wlast    (dram.w_last),
        .S00_AXI_0_wready   (dram.w_ready),
        .S00_AXI_0_wstrb    (dram.w_strb),
        .S00_AXI_0_wvalid   (dram.w_valid),
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

// -------------------------
// Clocking system and RESET
// -------------------------
    logic clk;
    logic rtc;
    logic pll_locked;
    logic rst_n, rst;

    logic sys_rst_n_c;
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
    .clk_out3 ( pcie_axi_clk  ), // 250 Mhz pcie and hbm clk
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

    logic master_areset;

    // ndmreset_n is driven high when pll locks and the board releases his external reset
    // then the logic can be resetted from the hbm_xdma_interface
    rstgen i_rstgen_main (
        .clk_i        ( clk                      ),
        .rst_ni       ( pll_locked & (!master_areset) & sys_rst_n_c),
        .test_mode_i  ( test_en                  ),
        .rst_no       ( ndmreset_n               ),
        .init_no      (                          ) // keep open
    );

    logic hbm_apb_areset_n;

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
