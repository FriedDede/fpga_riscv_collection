// Copyright 2026 Politecnico di Milano.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

// Description: VexiiRiscv (hw/cores/vex2/VexiiRiscv) in its own clock domain. VexiiRiscvU55 is generated
//              by the Makefile in build/<run>/vexiiriscv/VexiiRiscvU55.v (hw/cores/vex2/GenVexiiRiscvU55.scala:
//              RV32IM, 4 KiB I$, 8 KiB write-back D$, reset vector 0x0). Its three AXI masters
//              - ibus:  I$ refills (read only, 64 bit, 8 beat bursts)
//              - dbus:  D$ refills and writebacks (64 bit, 8 beat bursts)
//              - iobus: uncached accesses to the bootrom, CLINT and peripherals (32 bit, single beat)
//              have no id (one transaction in flight each): id 0. They are upsized to AxiDataWidth
//              when narrower and crossed to the cluster domain with axi_cdc. The interrupts can come
//              from any domain and are synchronized here. The time csr (rdtime) reads 0.
// Author: Andrea Motta
`include "axi_assign.svh"

module vex2_cd_wrapper #(
    parameter int unsigned AxiAddrWidth = 32,   // VexiiRiscvU55: 32
    parameter int unsigned AxiDataWidth = 64,   // cluster side, >= 64
    parameter int unsigned AxiUserWidth = 1,
    parameter int unsigned AxiIdWidth   = 1,    // VexiiRiscvU55: no id (always 0)
    parameter int unsigned CdcLogDepth  = 2
)(
    // core domain
    input  logic        clk_core_i,
    // cluster domain
    input  logic        clk_cluster_i,
    input  logic        rst_cluster_ni,
    // asynchronous reset, released synchronously to clk_core_i inside
    input  logic        rst_ni,
    input  logic [31:0] hart_id_i,      // core index in the cluster
    // interrupts, any domain
    input  logic        timer_irq_i,    // mtip
    input  logic        soft_irq_i,     // msip
    input  logic        ext_irq_i,      // meip
    // cluster domain AXI masters
    AXI_BUS.Master      ibus,           // I$ refills (read only)
    AXI_BUS.Master      dbus,           // D$ refills and writebacks
    AXI_BUS.Master      iobus           // uncached accesses
);

    // ibus, dbus, iobus
    localparam int unsigned NumPorts = 3;

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

    logic [2:0] irq_async, irq;
    assign irq_async = {ext_irq_i, soft_irq_i, timer_irq_i};
    for (genvar k = 0; k < 3; ++k) begin : gen_sync_irq
        sync i_sync_irq (.clk_i(clk_core_i), .rst_ni(rst_core_n), .serial_i(irq_async[k]), .serial_o(irq[k]));
    end

// -----------------
// Core
// -----------------
    AXI_BUS #(
        .AXI_ADDR_WIDTH ( AxiAddrWidth ),
        .AXI_DATA_WIDTH ( 64           ),
        .AXI_ID_WIDTH   ( AxiIdWidth   ),
        .AXI_USER_WIDTH ( AxiUserWidth )
    ) axi_ibus(), axi_dbus();
    AXI_BUS #(
        .AXI_ADDR_WIDTH ( AxiAddrWidth ),
        .AXI_DATA_WIDTH ( 32           ),
        .AXI_ID_WIDTH   ( AxiIdWidth   ),
        .AXI_USER_WIDTH ( AxiUserWidth )
    ) axi_iobus();

    // signals the core does not drive: id 0, no atomics, lock, qos, region and user signals.
    // The ibus is read only, the iobus issues single beat INCR transactions
    assign axi_ibus.aw_valid  = 1'b0;
    assign axi_ibus.aw_addr   = '0;
    assign axi_ibus.aw_len    = '0;
    assign axi_ibus.aw_size   = '0;
    assign axi_ibus.aw_burst  = '0;
    assign axi_ibus.aw_cache  = '0;
    assign axi_ibus.aw_prot   = '0;
    assign axi_ibus.w_valid   = 1'b0;
    assign axi_ibus.w_data    = '0;
    assign axi_ibus.w_strb    = '0;
    assign axi_ibus.w_last    = 1'b0;
    assign axi_ibus.b_ready   = 1'b1;
    assign axi_iobus.aw_len   = '0;
    assign axi_iobus.aw_burst = axi_pkg::BURST_INCR;
    assign axi_iobus.ar_len   = '0;
    assign axi_iobus.ar_burst = axi_pkg::BURST_INCR;

    `define VEX2_TIE_AXI(bus) \
        assign bus.aw_id     = '0; \
        assign bus.aw_lock   = 1'b0; \
        assign bus.aw_qos    = '0; \
        assign bus.aw_region = '0; \
        assign bus.aw_atop   = '0; \
        assign bus.aw_user   = '0; \
        assign bus.w_user    = '0; \
        assign bus.ar_id     = '0; \
        assign bus.ar_lock   = 1'b0; \
        assign bus.ar_qos    = '0; \
        assign bus.ar_region = '0; \
        assign bus.ar_user   = '0;
    `VEX2_TIE_AXI(axi_ibus)
    `VEX2_TIE_AXI(axi_dbus)
    `VEX2_TIE_AXI(axi_iobus)
    `undef VEX2_TIE_AXI

    // VexiiRiscv reset is active high
    VexiiRiscvU55 i_vex (
        .clk                                           ( clk_core_i              ),
        .reset                                         ( ~rst_core_n             ),
        .PrivilegedPlugin_api_harts_0_hartId           ( hart_id_i               ),
        .PrivilegedPlugin_logic_rdtime                 ( 64'd0                   ),
        .PrivilegedPlugin_logic_harts_0_int_m_timer    ( irq[0]                  ),
        .PrivilegedPlugin_logic_harts_0_int_m_software ( irq[1]                  ),
        .PrivilegedPlugin_logic_harts_0_int_m_external ( irq[2]                  ),
        // ibus
        .FetchL1Axi4Plugin_logic_axi_ar_valid          ( axi_ibus.ar_valid       ),
        .FetchL1Axi4Plugin_logic_axi_ar_ready          ( axi_ibus.ar_ready       ),
        .FetchL1Axi4Plugin_logic_axi_ar_payload_addr   ( axi_ibus.ar_addr        ),
        .FetchL1Axi4Plugin_logic_axi_ar_payload_len    ( axi_ibus.ar_len         ),
        .FetchL1Axi4Plugin_logic_axi_ar_payload_size   ( axi_ibus.ar_size        ),
        .FetchL1Axi4Plugin_logic_axi_ar_payload_burst  ( axi_ibus.ar_burst       ),
        .FetchL1Axi4Plugin_logic_axi_ar_payload_cache  ( axi_ibus.ar_cache       ),
        .FetchL1Axi4Plugin_logic_axi_ar_payload_prot   ( axi_ibus.ar_prot        ),
        .FetchL1Axi4Plugin_logic_axi_r_valid           ( axi_ibus.r_valid        ),
        .FetchL1Axi4Plugin_logic_axi_r_ready           ( axi_ibus.r_ready        ),
        .FetchL1Axi4Plugin_logic_axi_r_payload_data    ( axi_ibus.r_data         ),
        .FetchL1Axi4Plugin_logic_axi_r_payload_resp    ( axi_ibus.r_resp         ),
        .FetchL1Axi4Plugin_logic_axi_r_payload_last    ( axi_ibus.r_last         ),
        // dbus
        .LsuL1Axi4Plugin_logic_axi_aw_valid            ( axi_dbus.aw_valid       ),
        .LsuL1Axi4Plugin_logic_axi_aw_ready            ( axi_dbus.aw_ready       ),
        .LsuL1Axi4Plugin_logic_axi_aw_payload_addr     ( axi_dbus.aw_addr        ),
        .LsuL1Axi4Plugin_logic_axi_aw_payload_len      ( axi_dbus.aw_len         ),
        .LsuL1Axi4Plugin_logic_axi_aw_payload_size     ( axi_dbus.aw_size        ),
        .LsuL1Axi4Plugin_logic_axi_aw_payload_burst    ( axi_dbus.aw_burst       ),
        .LsuL1Axi4Plugin_logic_axi_aw_payload_cache    ( axi_dbus.aw_cache       ),
        .LsuL1Axi4Plugin_logic_axi_aw_payload_prot     ( axi_dbus.aw_prot        ),
        .LsuL1Axi4Plugin_logic_axi_w_valid             ( axi_dbus.w_valid        ),
        .LsuL1Axi4Plugin_logic_axi_w_ready             ( axi_dbus.w_ready        ),
        .LsuL1Axi4Plugin_logic_axi_w_payload_data      ( axi_dbus.w_data         ),
        .LsuL1Axi4Plugin_logic_axi_w_payload_strb      ( axi_dbus.w_strb         ),
        .LsuL1Axi4Plugin_logic_axi_w_payload_last      ( axi_dbus.w_last         ),
        .LsuL1Axi4Plugin_logic_axi_b_valid             ( axi_dbus.b_valid        ),
        .LsuL1Axi4Plugin_logic_axi_b_ready             ( axi_dbus.b_ready        ),
        .LsuL1Axi4Plugin_logic_axi_b_payload_resp      ( axi_dbus.b_resp         ),
        .LsuL1Axi4Plugin_logic_axi_ar_valid            ( axi_dbus.ar_valid       ),
        .LsuL1Axi4Plugin_logic_axi_ar_ready            ( axi_dbus.ar_ready       ),
        .LsuL1Axi4Plugin_logic_axi_ar_payload_addr     ( axi_dbus.ar_addr        ),
        .LsuL1Axi4Plugin_logic_axi_ar_payload_len      ( axi_dbus.ar_len         ),
        .LsuL1Axi4Plugin_logic_axi_ar_payload_size     ( axi_dbus.ar_size        ),
        .LsuL1Axi4Plugin_logic_axi_ar_payload_burst    ( axi_dbus.ar_burst       ),
        .LsuL1Axi4Plugin_logic_axi_ar_payload_cache    ( axi_dbus.ar_cache       ),
        .LsuL1Axi4Plugin_logic_axi_ar_payload_prot     ( axi_dbus.ar_prot        ),
        .LsuL1Axi4Plugin_logic_axi_r_valid             ( axi_dbus.r_valid        ),
        .LsuL1Axi4Plugin_logic_axi_r_ready             ( axi_dbus.r_ready        ),
        .LsuL1Axi4Plugin_logic_axi_r_payload_data      ( axi_dbus.r_data         ),
        .LsuL1Axi4Plugin_logic_axi_r_payload_resp      ( axi_dbus.r_resp         ),
        .LsuL1Axi4Plugin_logic_axi_r_payload_last      ( axi_dbus.r_last         ),
        // iobus
        .LsuCachelessAxi4Plugin_logic_axi_aw_valid         ( axi_iobus.aw_valid  ),
        .LsuCachelessAxi4Plugin_logic_axi_aw_ready         ( axi_iobus.aw_ready  ),
        .LsuCachelessAxi4Plugin_logic_axi_aw_payload_addr  ( axi_iobus.aw_addr   ),
        .LsuCachelessAxi4Plugin_logic_axi_aw_payload_size  ( axi_iobus.aw_size   ),
        .LsuCachelessAxi4Plugin_logic_axi_aw_payload_cache ( axi_iobus.aw_cache  ),
        .LsuCachelessAxi4Plugin_logic_axi_aw_payload_prot  ( axi_iobus.aw_prot   ),
        .LsuCachelessAxi4Plugin_logic_axi_w_valid          ( axi_iobus.w_valid   ),
        .LsuCachelessAxi4Plugin_logic_axi_w_ready          ( axi_iobus.w_ready   ),
        .LsuCachelessAxi4Plugin_logic_axi_w_payload_data   ( axi_iobus.w_data    ),
        .LsuCachelessAxi4Plugin_logic_axi_w_payload_strb   ( axi_iobus.w_strb    ),
        .LsuCachelessAxi4Plugin_logic_axi_w_payload_last   ( axi_iobus.w_last    ),
        .LsuCachelessAxi4Plugin_logic_axi_b_valid          ( axi_iobus.b_valid   ),
        .LsuCachelessAxi4Plugin_logic_axi_b_ready          ( axi_iobus.b_ready   ),
        .LsuCachelessAxi4Plugin_logic_axi_b_payload_resp   ( axi_iobus.b_resp    ),
        .LsuCachelessAxi4Plugin_logic_axi_ar_valid         ( axi_iobus.ar_valid  ),
        .LsuCachelessAxi4Plugin_logic_axi_ar_ready         ( axi_iobus.ar_ready  ),
        .LsuCachelessAxi4Plugin_logic_axi_ar_payload_addr  ( axi_iobus.ar_addr   ),
        .LsuCachelessAxi4Plugin_logic_axi_ar_payload_size  ( axi_iobus.ar_size   ),
        .LsuCachelessAxi4Plugin_logic_axi_ar_payload_cache ( axi_iobus.ar_cache  ),
        .LsuCachelessAxi4Plugin_logic_axi_ar_payload_prot  ( axi_iobus.ar_prot   ),
        .LsuCachelessAxi4Plugin_logic_axi_r_valid          ( axi_iobus.r_valid   ),
        .LsuCachelessAxi4Plugin_logic_axi_r_ready          ( axi_iobus.r_ready   ),
        .LsuCachelessAxi4Plugin_logic_axi_r_payload_data   ( axi_iobus.r_data    ),
        .LsuCachelessAxi4Plugin_logic_axi_r_payload_resp   ( axi_iobus.r_resp    ),
        .LsuCachelessAxi4Plugin_logic_axi_r_payload_last   ( axi_iobus.r_last    )
    );

// -----------------
// Data width conversion and clock domain crossings
// -----------------
    AXI_BUS #(
        .AXI_ADDR_WIDTH ( AxiAddrWidth ),
        .AXI_DATA_WIDTH ( AxiDataWidth ),
        .AXI_ID_WIDTH   ( AxiIdWidth   ),
        .AXI_USER_WIDTH ( AxiUserWidth )
    ) axi_core[NumPorts-1:0](), axi_cluster[NumPorts-1:0]();

    // ibus and dbus: 64 bit
    for (genvar k = 0; k < 2; ++k) begin : gen_dw_cache
        AXI_BUS #(
            .AXI_ADDR_WIDTH ( AxiAddrWidth ),
            .AXI_DATA_WIDTH ( 64           ),
            .AXI_ID_WIDTH   ( AxiIdWidth   ),
            .AXI_USER_WIDTH ( AxiUserWidth )
        ) axi_vex();
        if (k == 0) begin : gen_i
            `AXI_ASSIGN(axi_vex, axi_ibus)
        end else begin : gen_d
            `AXI_ASSIGN(axi_vex, axi_dbus)
        end
        if (AxiDataWidth != 64) begin : gen_dw
            axi_dw_converter_intf #(
                .AXI_ID_WIDTH            ( AxiIdWidth   ),
                .AXI_ADDR_WIDTH          ( AxiAddrWidth ),
                .AXI_SLV_PORT_DATA_WIDTH ( 64           ),
                .AXI_MST_PORT_DATA_WIDTH ( AxiDataWidth ),
                .AXI_USER_WIDTH          ( AxiUserWidth ),
                .AXI_MAX_READS           ( 2            )
            ) i_dw (
                .clk_i  ( clk_core_i  ),
                .rst_ni ( rst_core_n  ),
                .slv    ( axi_vex     ),
                .mst    ( axi_core[k] )
            );
        end else begin : gen_no_dw
            `AXI_ASSIGN(axi_core[k], axi_vex)
        end
    end

    // iobus: 32 bit, always upsized
    axi_dw_converter_intf #(
        .AXI_ID_WIDTH            ( AxiIdWidth   ),
        .AXI_ADDR_WIDTH          ( AxiAddrWidth ),
        .AXI_SLV_PORT_DATA_WIDTH ( 32           ),
        .AXI_MST_PORT_DATA_WIDTH ( AxiDataWidth ),
        .AXI_USER_WIDTH          ( AxiUserWidth ),
        .AXI_MAX_READS           ( 1            )
    ) i_dw_io (
        .clk_i  ( clk_core_i  ),
        .rst_ni ( rst_core_n  ),
        .slv    ( axi_iobus   ),
        .mst    ( axi_core[2] )
    );

    for (genvar k = 0; k < NumPorts; ++k) begin : gen_cdc
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

    `AXI_ASSIGN(ibus,  axi_cluster[0])
    `AXI_ASSIGN(dbus,  axi_cluster[1])
    `AXI_ASSIGN(iobus, axi_cluster[2])

endmodule
