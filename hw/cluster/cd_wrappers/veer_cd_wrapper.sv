// Copyright 2024 Politecnico di Milano.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

// Description: VeeR-EL2 core (with its DCCM/I$ srams) in its own clock domain.
//              The AXI ports are in the cluster (crossbar) domain, crossed with axi_cdc,
//              the interrupts can come from any domain and are synchronized here.
// Author: Andrea Motta

module veer_cd_wrapper
    import el2_pkg::*;
#(
`include "el2_param.vh"
    ,
    parameter int unsigned AxiAddrWidth   = 32,
    parameter int unsigned AxiDataWidth   = 64,
    parameter int unsigned AxiUserWidth   = 1,
    parameter int unsigned AxiIdWidth     = 4,    // ifu/lsu masters, >= pt.IFU_BUS_TAG/pt.LSU_BUS_TAG
    parameter int unsigned AxiDmaIdWidth  = 5,    // dma slave, <= pt.DMA_BUS_TAG
    parameter logic [31:0] BootAddr       = 32'h0000_0000,
    parameter int unsigned CoreId         = 0,    // core index in the cluster, mhartid = {CoreId, 4'b0}
    parameter int unsigned CdcLogDepth    = 2
)(
    // core domain
    input  logic                      clk_core_i,
    // cluster domain
    input  logic                      clk_cluster_i,
    input  logic                      rst_cluster_ni,
    // asynchronous reset, released synchronously to clk_core_i inside
    input  logic                      rst_ni,
    // interrupts, any domain
    input  logic                      timer_irq_i,
    input  logic                      soft_irq_i,
    input  logic [pt.PIC_TOTAL_INT:1] ext_irq_i,
    // cluster domain AXI ports
    AXI_BUS.Master                    ifu,
    AXI_BUS.Master                    lsu,
    AXI_BUS.Slave                     dma
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

    logic                      timer_irq, soft_irq;
    logic [pt.PIC_TOTAL_INT:1] ext_irq;
    sync i_sync_timer (.clk_i(clk_core_i), .rst_ni(rst_core_n), .serial_i(timer_irq_i), .serial_o(timer_irq));
    sync i_sync_soft  (.clk_i(clk_core_i), .rst_ni(rst_core_n), .serial_i(soft_irq_i),  .serial_o(soft_irq));
    for (genvar k = 1; k <= pt.PIC_TOTAL_INT; ++k) begin : gen_sync_ext
        sync i_sync_ext (.clk_i(clk_core_i), .rst_ni(rst_core_n), .serial_i(ext_irq_i[k]), .serial_o(ext_irq[k]));
    end

// -----------------
// Clock domain crossings
// -----------------
    AXI_BUS #(
        .AXI_ADDR_WIDTH ( AxiAddrWidth ),
        .AXI_DATA_WIDTH ( AxiDataWidth ),
        .AXI_ID_WIDTH   ( AxiIdWidth   ),
        .AXI_USER_WIDTH ( AxiUserWidth )
    ) axi_ifu(), axi_lsu();
    AXI_BUS #(
        .AXI_ADDR_WIDTH ( AxiAddrWidth  ),
        .AXI_DATA_WIDTH ( AxiDataWidth  ),
        .AXI_ID_WIDTH   ( AxiDmaIdWidth ),
        .AXI_USER_WIDTH ( AxiUserWidth  )
    ) axi_dma();

    axi_cdc_intf #(
        .AXI_ID_WIDTH   ( AxiIdWidth   ),
        .AXI_ADDR_WIDTH ( AxiAddrWidth ),
        .AXI_DATA_WIDTH ( AxiDataWidth ),
        .AXI_USER_WIDTH ( AxiUserWidth ),
        .LOG_DEPTH      ( CdcLogDepth  )
    ) i_cdc_ifu (
        .src_clk_i  ( clk_core_i     ),
        .src_rst_ni ( rst_core_n     ),
        .src        ( axi_ifu        ),
        .dst_clk_i  ( clk_cluster_i  ),
        .dst_rst_ni ( rst_cluster_ni ),
        .dst        ( ifu            )
    );
    axi_cdc_intf #(
        .AXI_ID_WIDTH   ( AxiIdWidth   ),
        .AXI_ADDR_WIDTH ( AxiAddrWidth ),
        .AXI_DATA_WIDTH ( AxiDataWidth ),
        .AXI_USER_WIDTH ( AxiUserWidth ),
        .LOG_DEPTH      ( CdcLogDepth  )
    ) i_cdc_lsu (
        .src_clk_i  ( clk_core_i     ),
        .src_rst_ni ( rst_core_n     ),
        .src        ( axi_lsu        ),
        .dst_clk_i  ( clk_cluster_i  ),
        .dst_rst_ni ( rst_cluster_ni ),
        .dst        ( lsu            )
    );
    axi_cdc_intf #(
        .AXI_ID_WIDTH   ( AxiDmaIdWidth ),
        .AXI_ADDR_WIDTH ( AxiAddrWidth  ),
        .AXI_DATA_WIDTH ( AxiDataWidth  ),
        .AXI_USER_WIDTH ( AxiUserWidth  ),
        .LOG_DEPTH      ( CdcLogDepth   )
    ) i_cdc_dma (
        .src_clk_i  ( clk_cluster_i  ),
        .src_rst_ni ( rst_cluster_ni ),
        .src        ( dma            ),
        .dst_clk_i  ( clk_core_i     ),
        .dst_rst_ni ( rst_core_n     ),
        .dst        ( axi_dma        )
    );

// -----------------
// Core
// -----------------
    // VeeR bus tags are narrower than the xbar id: zero extend on requests, truncate on responses
    logic [pt.IFU_BUS_TAG-1:0] ifu_awid, ifu_arid;
    logic [pt.LSU_BUS_TAG-1:0] lsu_awid, lsu_arid;
    assign axi_ifu.aw_id = AxiIdWidth'(ifu_awid);
    assign axi_ifu.ar_id = AxiIdWidth'(ifu_arid);
    assign axi_lsu.aw_id = AxiIdWidth'(lsu_awid);
    assign axi_lsu.ar_id = AxiIdWidth'(lsu_arid);
    // no atomics and no user signals on VeeR
    assign axi_ifu.aw_atop = '0;
    assign axi_lsu.aw_atop = '0;
    assign axi_ifu.aw_user = '0;
    assign axi_lsu.aw_user = '0;
    assign axi_ifu.ar_user = '0;
    assign axi_lsu.ar_user = '0;
    assign axi_ifu.w_user  = '0;
    assign axi_lsu.w_user  = '0;

    // DMA tag (pt.DMA_BUS_TAG) is wider than the xbar id
    logic [pt.DMA_BUS_TAG-1:0] dma_bid, dma_rid;
    assign axi_dma.b_id   = dma_bid[AxiDmaIdWidth-1:0];
    assign axi_dma.r_id   = dma_rid[AxiDmaIdWidth-1:0];
    assign axi_dma.b_user = '0;
    assign axi_dma.r_user = '0;

    // VeeR memories: DCCM, I$ (and ICCM if enabled)
    el2_mem_if el2_mem_export ();
    veer_fpga_mem #(
        .pt(pt)
    ) i_veer_mem (
        .mem_export(el2_mem_export)
    );

    el2_veer_wrapper #(
        .pt(pt)
    ) veer_instance (
        .clk                    (clk_core_i),
        .rst_l                  (rst_core_n),
        .dbg_rst_l              (rst_core_n),
        .rst_vec                (BootAddr[31:1]),
        .nmi_int                (1'b0),
        .nmi_vec                (BootAddr[31:1]),
        .jtag_id                ('0),
        .trace_rv_i_insn_ip     (),
        .trace_rv_i_address_ip  (),
        .trace_rv_i_valid_ip    (),
        .trace_rv_i_exception_ip(),
        .trace_rv_i_ecause_ip   (),
        .trace_rv_i_interrupt_ip(),
        .trace_rv_i_tval_ip     (),
        // LSU
        .lsu_axi_awvalid        (axi_lsu.aw_valid),
        .lsu_axi_awready        (axi_lsu.aw_ready),
        .lsu_axi_awid           (lsu_awid),
        .lsu_axi_awaddr         (axi_lsu.aw_addr),
        .lsu_axi_awregion       (axi_lsu.aw_region),
        .lsu_axi_awlen          (axi_lsu.aw_len),
        .lsu_axi_awsize         (axi_lsu.aw_size),
        .lsu_axi_awburst        (axi_lsu.aw_burst),
        .lsu_axi_awlock         (axi_lsu.aw_lock),
        .lsu_axi_awcache        (axi_lsu.aw_cache),
        .lsu_axi_awprot         (axi_lsu.aw_prot),
        .lsu_axi_awqos          (axi_lsu.aw_qos),
        .lsu_axi_wvalid         (axi_lsu.w_valid),
        .lsu_axi_wready         (axi_lsu.w_ready),
        .lsu_axi_wdata          (axi_lsu.w_data),
        .lsu_axi_wstrb          (axi_lsu.w_strb),
        .lsu_axi_wlast          (axi_lsu.w_last),
        .lsu_axi_bvalid         (axi_lsu.b_valid),
        .lsu_axi_bready         (axi_lsu.b_ready),
        .lsu_axi_bresp          (axi_lsu.b_resp),
        .lsu_axi_bid            (axi_lsu.b_id[pt.LSU_BUS_TAG-1:0]),
        .lsu_axi_arvalid        (axi_lsu.ar_valid),
        .lsu_axi_arready        (axi_lsu.ar_ready),
        .lsu_axi_arid           (lsu_arid),
        .lsu_axi_araddr         (axi_lsu.ar_addr),
        .lsu_axi_arregion       (axi_lsu.ar_region),
        .lsu_axi_arlen          (axi_lsu.ar_len),
        .lsu_axi_arsize         (axi_lsu.ar_size),
        .lsu_axi_arburst        (axi_lsu.ar_burst),
        .lsu_axi_arlock         (axi_lsu.ar_lock),
        .lsu_axi_arcache        (axi_lsu.ar_cache),
        .lsu_axi_arprot         (axi_lsu.ar_prot),
        .lsu_axi_arqos          (axi_lsu.ar_qos),
        .lsu_axi_rvalid         (axi_lsu.r_valid),
        .lsu_axi_rready         (axi_lsu.r_ready),
        .lsu_axi_rid            (axi_lsu.r_id[pt.LSU_BUS_TAG-1:0]),
        .lsu_axi_rdata          (axi_lsu.r_data),
        .lsu_axi_rresp          (axi_lsu.r_resp),
        .lsu_axi_rlast          (axi_lsu.r_last),
        // IFU (write channels are constant 0 inside the core)
        .ifu_axi_awvalid        (axi_ifu.aw_valid),
        .ifu_axi_awready        (axi_ifu.aw_ready),
        .ifu_axi_awid           (ifu_awid),
        .ifu_axi_awaddr         (axi_ifu.aw_addr),
        .ifu_axi_awregion       (axi_ifu.aw_region),
        .ifu_axi_awlen          (axi_ifu.aw_len),
        .ifu_axi_awsize         (axi_ifu.aw_size),
        .ifu_axi_awburst        (axi_ifu.aw_burst),
        .ifu_axi_awlock         (axi_ifu.aw_lock),
        .ifu_axi_awcache        (axi_ifu.aw_cache),
        .ifu_axi_awprot         (axi_ifu.aw_prot),
        .ifu_axi_awqos          (axi_ifu.aw_qos),
        .ifu_axi_wvalid         (axi_ifu.w_valid),
        .ifu_axi_wready         (axi_ifu.w_ready),
        .ifu_axi_wdata          (axi_ifu.w_data),
        .ifu_axi_wstrb          (axi_ifu.w_strb),
        .ifu_axi_wlast          (axi_ifu.w_last),
        .ifu_axi_bvalid         (axi_ifu.b_valid),
        .ifu_axi_bready         (axi_ifu.b_ready),
        .ifu_axi_bresp          (axi_ifu.b_resp),
        .ifu_axi_bid            (axi_ifu.b_id[pt.IFU_BUS_TAG-1:0]),
        .ifu_axi_arvalid        (axi_ifu.ar_valid),
        .ifu_axi_arready        (axi_ifu.ar_ready),
        .ifu_axi_arid           (ifu_arid),
        .ifu_axi_araddr         (axi_ifu.ar_addr),
        .ifu_axi_arregion       (axi_ifu.ar_region),
        .ifu_axi_arlen          (axi_ifu.ar_len),
        .ifu_axi_arsize         (axi_ifu.ar_size),
        .ifu_axi_arburst        (axi_ifu.ar_burst),
        .ifu_axi_arlock         (axi_ifu.ar_lock),
        .ifu_axi_arcache        (axi_ifu.ar_cache),
        .ifu_axi_arprot         (axi_ifu.ar_prot),
        .ifu_axi_arqos          (axi_ifu.ar_qos),
        .ifu_axi_rvalid         (axi_ifu.r_valid),
        .ifu_axi_rready         (axi_ifu.r_ready),
        .ifu_axi_rid            (axi_ifu.r_id[pt.IFU_BUS_TAG-1:0]),
        .ifu_axi_rdata          (axi_ifu.r_data),
        .ifu_axi_rresp          (axi_ifu.r_resp),
        .ifu_axi_rlast          (axi_ifu.r_last),
        // SB (debug system bus): no debugger attached, never issues requests
        .sb_axi_awvalid         (),
        .sb_axi_awready         (1'b0),
        .sb_axi_awid            (),
        .sb_axi_awaddr          (),
        .sb_axi_awregion        (),
        .sb_axi_awlen           (),
        .sb_axi_awsize          (),
        .sb_axi_awburst         (),
        .sb_axi_awlock          (),
        .sb_axi_awcache         (),
        .sb_axi_awprot          (),
        .sb_axi_awqos           (),
        .sb_axi_wvalid          (),
        .sb_axi_wready          (1'b0),
        .sb_axi_wdata           (),
        .sb_axi_wstrb           (),
        .sb_axi_wlast           (),
        .sb_axi_bvalid          (1'b0),
        .sb_axi_bready          (),
        .sb_axi_bresp           ('0),
        .sb_axi_bid             ('0),
        .sb_axi_arvalid         (),
        .sb_axi_arready         (1'b0),
        .sb_axi_arid            (),
        .sb_axi_araddr          (),
        .sb_axi_arregion        (),
        .sb_axi_arlen           (),
        .sb_axi_arsize          (),
        .sb_axi_arburst         (),
        .sb_axi_arlock          (),
        .sb_axi_arcache         (),
        .sb_axi_arprot          (),
        .sb_axi_arqos           (),
        .sb_axi_rvalid          (1'b0),
        .sb_axi_rready          (),
        .sb_axi_rid             ('0),
        .sb_axi_rdata           ('0),
        .sb_axi_rresp           ('0),
        .sb_axi_rlast           (1'b0),
        // DMA slave: alias window, bit 31 set to reach ICCM (0xE) / DCCM (0xF) regions
        .dma_axi_awvalid        (axi_dma.aw_valid),
        .dma_axi_awready        (axi_dma.aw_ready),
        .dma_axi_awid           (pt.DMA_BUS_TAG'(axi_dma.aw_id)),
        .dma_axi_awaddr         ({1'b1, axi_dma.aw_addr[30:0]}),
        .dma_axi_awsize         (axi_dma.aw_size),
        .dma_axi_awprot         (axi_dma.aw_prot),
        .dma_axi_awlen          (axi_dma.aw_len),
        .dma_axi_awburst        (axi_dma.aw_burst),
        .dma_axi_wvalid         (axi_dma.w_valid),
        .dma_axi_wready         (axi_dma.w_ready),
        .dma_axi_wdata          (axi_dma.w_data),
        .dma_axi_wstrb          (axi_dma.w_strb),
        .dma_axi_wlast          (axi_dma.w_last),
        .dma_axi_bvalid         (axi_dma.b_valid),
        .dma_axi_bready         (axi_dma.b_ready),
        .dma_axi_bresp          (axi_dma.b_resp),
        .dma_axi_bid            (dma_bid),
        .dma_axi_arvalid        (axi_dma.ar_valid),
        .dma_axi_arready        (axi_dma.ar_ready),
        .dma_axi_arid           (pt.DMA_BUS_TAG'(axi_dma.ar_id)),
        .dma_axi_araddr         ({1'b1, axi_dma.ar_addr[30:0]}),
        .dma_axi_arsize         (axi_dma.ar_size),
        .dma_axi_arprot         (axi_dma.ar_prot),
        .dma_axi_arlen          (axi_dma.ar_len),
        .dma_axi_arburst        (axi_dma.ar_burst),
        .dma_axi_rvalid         (axi_dma.r_valid),
        .dma_axi_rready         (axi_dma.r_ready),
        .dma_axi_rid            (dma_rid),
        .dma_axi_rdata          (axi_dma.r_data),
        .dma_axi_rresp          (axi_dma.r_resp),
        .dma_axi_rlast          (axi_dma.r_last),
        // buses run at core clock
        .lsu_bus_clk_en         (1'b1),
        .ifu_bus_clk_en         (1'b1),
        .dbg_bus_clk_en         (1'b1),
        .dma_bus_clk_en         (1'b1),
        .iccm_ecc_single_error  (),
        .iccm_ecc_double_error  (),
        .dccm_ecc_single_error  (),
        .dccm_ecc_double_error  (),
        .dccm_write_readback_error(),
        .el2_icache_export      (el2_mem_export.veer_icache_src),
        .el2_mem_export         (el2_mem_export.veer_sram_src),
        // mtip / msip from the CLINT, meip from the internal PIC
        .timer_int              (timer_irq),
        .soft_int               (soft_irq),
        .extintsrc_req          (ext_irq),
        .dec_tlu_perfcnt0       (),
        .dec_tlu_perfcnt1       (),
        .dec_tlu_perfcnt2       (),
        .dec_tlu_perfcnt3       (),
        // JTAG: no debugger, keep the TAP in reset
        .jtag_tck               (1'b0),
        .jtag_tms               (1'b0),
        .jtag_tdi               (1'b0),
        .jtag_trst_n            (1'b0),
        .jtag_tdo               (),
        .jtag_tdoEn             (),
        .core_id                (28'(CoreId)),
        // start running from rst_vec after reset
        .mpc_debug_halt_req     (1'b0),
        .mpc_debug_run_req      (1'b0),
        .mpc_reset_run_req      (1'b1),
        .mpc_debug_halt_ack     (),
        .mpc_debug_run_ack      (),
        .debug_brkpt_status     (),
        .i_cpu_halt_req         (1'b0),
        .o_cpu_halt_ack         (),
        .o_cpu_halt_status      (),
        .o_debug_mode_status    (),
        .i_cpu_run_req          (1'b0),
        .o_cpu_run_ack          (),
        .scan_mode              (1'b0),
        .mbist_mode             (1'b0),
        .dmi_core_enable        (1'b1),
        .dmi_uncore_enable      (1'b0),
        .dmi_uncore_en          (),
        .dmi_uncore_wr_en       (),
        .dmi_uncore_addr        (),
        .dmi_uncore_wdata       (),
        .dmi_uncore_rdata       ('0),
        .dmi_active             ()
    );

endmodule
