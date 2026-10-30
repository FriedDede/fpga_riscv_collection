// Copyright 2024 Politecnico di Milano.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

// Description: Snitch core (integer core, fpu, icache) in its own clock domain.
//              The three AXI masters are in the cluster (crossbar) domain, crossed with
//              axi_cdc, the interrupts can come from any domain and are synchronized here.
// Author: Andrea Motta
`include "axi_assign.svh"

module snitch_cd_wrapper #(
    parameter int unsigned                 AxiAddrWidth = 32,
    parameter int unsigned                 AxiDataWidth = 64,
    parameter int unsigned                 AxiUserWidth = 1,
    parameter int unsigned                 AxiIdWidth   = 4,
    parameter logic [31:0]                 BootAddr     = 32'h0000_0000,
    parameter snitch_pma_pkg::snitch_pma_t SnitchPMACfg = '{default: 0},
    parameter int unsigned                 CdcLogDepth  = 2
)(
    // core domain
    input  logic                    clk_core_i,
    // cluster domain
    input  logic                    clk_cluster_i,
    input  logic                    rst_cluster_ni,
    // asynchronous reset, released synchronously to clk_core_i inside
    input  logic                    rst_ni,
    input  logic [31:0]             hart_id_i,      // core index in the cluster
    // interrupts, any domain
    input  snitch_pkg::interrupts_t irq_i,
    // cluster domain AXI masters
    AXI_BUS.Master                  data_core,      // integer core lsu
    AXI_BUS.Master                  data_fpu,       // fpu lsu
    AXI_BUS.Master                  inst            // icache refill
);

// -----------------
// Reset and interrupts
// -----------------
    logic rst_core_n;
    rstgen i_rstgen_core (
        .clk_i        ( clk_core_i ),
        .rst_ni       ( rst_ni     ),
        .test_mode_i  ( 1'b0       ),
        .rst_no       ( rst_core_n ),
        .init_no      (            )
    );

    localparam int unsigned IrqWidth = $bits(snitch_pkg::interrupts_t);
    snitch_pkg::interrupts_t irq;
    for (genvar k = 0; k < IrqWidth; ++k) begin : gen_sync_irq
        sync i_sync_irq (.clk_i(clk_core_i), .rst_ni(rst_core_n), .serial_i(irq_i[k]), .serial_o(irq[k]));
    end

// -----------------
// Core
// -----------------
    snitch_cluster_pkg::narrow_out_req_t        axi_icache_snitch_req;
    snitch_cluster_pkg::narrow_out_resp_t       axi_icache_snitch_resp;
    snitch_cluster_pkg::narrow_out_req_t  [1:0] axi_data_snitch_req;
    snitch_cluster_pkg::narrow_out_resp_t [1:0] axi_data_snitch_resp;
    snitch_core_axi #(
        .AddrWidth          (AxiAddrWidth),
        .DataWidth          (AxiDataWidth),
        .IdWidthIn          (AxiIdWidth),
        .BootAddr           (BootAddr),
        .SnitchPMACfg       (SnitchPMACfg)
    ) i_snitch (
        .clk_i                  (clk_core_i),
        .rst_ni                 (rst_core_n),
        .hart_id_i              (hart_id_i),
        .irq_i                  (irq),
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

// -----------------
// Clock domain crossings
// -----------------
    // 0: integer core lsu, 1: fpu lsu, 2: icache
    AXI_BUS #(
        .AXI_ADDR_WIDTH ( AxiAddrWidth ),
        .AXI_DATA_WIDTH ( AxiDataWidth ),
        .AXI_ID_WIDTH   ( AxiIdWidth   ),
        .AXI_USER_WIDTH ( AxiUserWidth )
    ) axi_core[2:0](), axi_cluster[2:0]();

    `AXI_ASSIGN_FROM_REQ (axi_core[0], axi_data_snitch_req[0])
    `AXI_ASSIGN_TO_RESP  (axi_data_snitch_resp[0], axi_core[0])
    `AXI_ASSIGN_FROM_REQ (axi_core[1], axi_data_snitch_req[1])
    `AXI_ASSIGN_TO_RESP  (axi_data_snitch_resp[1], axi_core[1])
    `AXI_ASSIGN_FROM_REQ (axi_core[2], axi_icache_snitch_req)
    `AXI_ASSIGN_TO_RESP  (axi_icache_snitch_resp, axi_core[2])

    for (genvar k = 0; k < 3; ++k) begin : gen_cdc
        axi_cdc_intf #(
            .AXI_ID_WIDTH   ( AxiIdWidth   ),
            .AXI_ADDR_WIDTH ( AxiAddrWidth ),
            .AXI_DATA_WIDTH ( AxiDataWidth ),
            .AXI_USER_WIDTH ( AxiUserWidth ),
            .LOG_DEPTH      ( CdcLogDepth  )
        ) i_cdc (
            .src_clk_i  ( clk_core_i     ),
            .src_rst_ni ( rst_core_n     ),
            .src        ( axi_core[k]    ),
            .dst_clk_i  ( clk_cluster_i  ),
            .dst_rst_ni ( rst_cluster_ni ),
            .dst        ( axi_cluster[k] )
        );
    end

    `AXI_ASSIGN(data_core, axi_cluster[0])
    `AXI_ASSIGN(data_fpu,  axi_cluster[1])
    `AXI_ASSIGN(inst,      axi_cluster[2])

endmodule
