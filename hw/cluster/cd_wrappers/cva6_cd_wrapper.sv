// Copyright 2024 Politecnico di Milano.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

// Description: CVA6 core in its own clock domain. The AXI master is in the cluster
//              (crossbar) domain, crossed with axi_cdc, the interrupts can come from any
//              domain and are synchronized here.
// Author: Andrea Motta
`include "axi_typedef.svh"
`include "axi_assign.svh"

module cva6_cd_wrapper #(
    parameter int unsigned AxiAddrWidth = 32,
    parameter int unsigned AxiDataWidth = 64,
    parameter int unsigned AxiUserWidth = 1,
    parameter int unsigned AxiIdWidth   = 4,
    parameter logic [63:0] BootAddr     = 64'h0000_0000,
    parameter int unsigned CdcLogDepth  = 2
)(
    // core domain
    input  logic        clk_core_i,
    // cluster domain
    input  logic        clk_cluster_i,
    input  logic        rst_cluster_ni,
    // asynchronous reset, released synchronously to clk_core_i inside
    input  logic        rst_ni,
    input  logic [63:0] hart_id_i,      // core index in the cluster
    // interrupts, any domain
    input  logic [1:0]  irq_i,          // meip, seip
    input  logic        ipi_i,          // msip
    input  logic        time_irq_i,     // mtip
    input  logic        debug_req_i,
    // cluster domain AXI master
    AXI_BUS.Master      noc
);

    typedef logic [AxiAddrWidth-1:0]   addr_t;
    typedef logic [AxiDataWidth-1:0]   data_t;
    typedef logic [AxiDataWidth/8-1:0] strb_t;
    typedef logic [AxiUserWidth-1:0]   user_t;
    typedef logic [AxiIdWidth-1:0]     id_t;
    `AXI_TYPEDEF_ALL(cva6_out, addr_t, id_t, data_t, strb_t, user_t)

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

    logic [4:0] irq_async, irq;
    assign irq_async = {debug_req_i, time_irq_i, ipi_i, irq_i};
    for (genvar k = 0; k < 5; ++k) begin : gen_sync_irq
        sync i_sync_irq (.clk_i(clk_core_i), .rst_ni(rst_core_n), .serial_i(irq_async[k]), .serial_o(irq[k]));
    end

// -----------------
// Core
// -----------------
    cva6_out_req_t  cva6_req;
    cva6_out_resp_t cva6_resp;

    cva6 #(
        .noc_req_t  (cva6_out_req_t),
        .noc_resp_t (cva6_out_resp_t)
    ) cva6_instance (
        .clk_i          (clk_core_i),
        .rst_ni         (rst_core_n),
        .boot_addr_i    (BootAddr),
        .hart_id_i      (hart_id_i),
        .irq_i          (irq[1:0]),
        .ipi_i          (irq[2]),
        .time_irq_i     (irq[3]),
        .debug_req_i    (irq[4]),
        .rvfi_probes_o  (),
        .cvxif_req_o    (),
        .cvxif_resp_i   ('0),
        .noc_req_o      (cva6_req),
        .noc_resp_i     (cva6_resp)
    );

// -----------------
// Clock domain crossing
// -----------------
    AXI_BUS #(
        .AXI_ADDR_WIDTH ( AxiAddrWidth ),
        .AXI_DATA_WIDTH ( AxiDataWidth ),
        .AXI_ID_WIDTH   ( AxiIdWidth   ),
        .AXI_USER_WIDTH ( AxiUserWidth )
    ) axi_core();

    `AXI_ASSIGN_FROM_REQ(axi_core, cva6_req)
    `AXI_ASSIGN_TO_RESP(cva6_resp, axi_core)

    axi_cdc_intf #(
        .AXI_ID_WIDTH   ( AxiIdWidth   ),
        .AXI_ADDR_WIDTH ( AxiAddrWidth ),
        .AXI_DATA_WIDTH ( AxiDataWidth ),
        .AXI_USER_WIDTH ( AxiUserWidth ),
        .LOG_DEPTH      ( CdcLogDepth  )
    ) i_cdc (
        .src_clk_i  ( clk_core_i     ),
        .src_rst_ni ( rst_core_n     ),
        .src        ( axi_core       ),
        .dst_clk_i  ( clk_cluster_i  ),
        .dst_rst_ni ( rst_cluster_ni ),
        .dst        ( noc            )
    );

endmodule
