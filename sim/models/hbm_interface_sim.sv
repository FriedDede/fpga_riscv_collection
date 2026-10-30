// Copyright 2024 Politecnico di Milano.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

// Description: simulation model of the hbm_interface block design (qdma_interface.tcl).
//              S00 is a behavioral AXI4 memory (INCR/FIXED bursts, in order responses),
//              S01..S11 are never ready, PCIe is not modeled and master_areset_o_0 is never
//              asserted.
//              Preload with +DRAM_HEX=<file> (objcopy -O verilog, addresses relative to HBM).
// Author: Andrea Motta

// ports of a channel that is not modeled, outputs driven to 0 in the module body
`define HBM_SIM_UNUSED_CHANNEL(prefix)                                        \
    input  logic        axi_clk_cluster_``prefix,                           \
    input  logic [33:0] prefix``_AXI_0_araddr,  prefix``_AXI_0_awaddr,      \
    input  logic [1:0]  prefix``_AXI_0_arburst, prefix``_AXI_0_awburst,     \
    input  logic [3:0]  prefix``_AXI_0_arcache, prefix``_AXI_0_awcache,     \
    input  logic [11:0] prefix``_AXI_0_arid,    prefix``_AXI_0_awid,        \
    input  logic [7:0]  prefix``_AXI_0_arlen,   prefix``_AXI_0_awlen,       \
    input  logic        prefix``_AXI_0_arlock,  prefix``_AXI_0_awlock,      \
    input  logic [2:0]  prefix``_AXI_0_arprot,  prefix``_AXI_0_awprot,      \
    input  logic [3:0]  prefix``_AXI_0_arqos,   prefix``_AXI_0_awqos,       \
    input  logic [2:0]  prefix``_AXI_0_arsize,  prefix``_AXI_0_awsize,      \
    input  logic        prefix``_AXI_0_arvalid, prefix``_AXI_0_awvalid,     \
    output logic        prefix``_AXI_0_arready, prefix``_AXI_0_awready,     \
    output logic [11:0] prefix``_AXI_0_bid,     prefix``_AXI_0_rid,         \
    input  logic        prefix``_AXI_0_bready,  prefix``_AXI_0_rready,      \
    output logic [1:0]  prefix``_AXI_0_bresp,   prefix``_AXI_0_rresp,       \
    output logic        prefix``_AXI_0_bvalid,  prefix``_AXI_0_rvalid,      \
    output logic        prefix``_AXI_0_rlast,                               \
    output logic [63:0] prefix``_AXI_0_rdata,                               \
    input  logic [63:0] prefix``_AXI_0_wdata,                               \
    input  logic        prefix``_AXI_0_wlast,   prefix``_AXI_0_wvalid,      \
    output logic        prefix``_AXI_0_wready,                              \
    input  logic [7:0]  prefix``_AXI_0_wstrb,

`define HBM_SIM_UNUSED_CHANNEL_TIE(prefix)                                    \
    assign {prefix``_AXI_0_arready, prefix``_AXI_0_awready, prefix``_AXI_0_wready,  \
            prefix``_AXI_0_bvalid, prefix``_AXI_0_rvalid, prefix``_AXI_0_rlast,     \
            prefix``_AXI_0_bid, prefix``_AXI_0_rid, prefix``_AXI_0_bresp,           \
            prefix``_AXI_0_rresp, prefix``_AXI_0_rdata} = '0;

module hbm_interface (
    input  logic        HBM_REF_CLK_0_0,
    input  logic        axi_clk_cluster_S00,
    input  logic [33:0] S00_AXI_0_araddr,
    input  logic [1:0]  S00_AXI_0_arburst,
    input  logic [3:0]  S00_AXI_0_arcache,
    input  logic [11:0] S00_AXI_0_arid,
    input  logic [7:0]  S00_AXI_0_arlen,
    input  logic        S00_AXI_0_arlock,
    input  logic [2:0]  S00_AXI_0_arprot,
    input  logic [3:0]  S00_AXI_0_arqos,
    output logic        S00_AXI_0_arready,
    input  logic [2:0]  S00_AXI_0_arsize,
    input  logic        S00_AXI_0_arvalid,
    input  logic [33:0] S00_AXI_0_awaddr,
    input  logic [1:0]  S00_AXI_0_awburst,
    input  logic [3:0]  S00_AXI_0_awcache,
    input  logic [11:0] S00_AXI_0_awid,
    input  logic [7:0]  S00_AXI_0_awlen,
    input  logic        S00_AXI_0_awlock,
    input  logic [2:0]  S00_AXI_0_awprot,
    input  logic [3:0]  S00_AXI_0_awqos,
    output logic        S00_AXI_0_awready,
    input  logic [2:0]  S00_AXI_0_awsize,
    input  logic        S00_AXI_0_awvalid,
    output logic [11:0] S00_AXI_0_bid,
    input  logic        S00_AXI_0_bready,
    output logic [1:0]  S00_AXI_0_bresp,
    output logic        S00_AXI_0_bvalid,
    output logic [63:0] S00_AXI_0_rdata,
    output logic [11:0] S00_AXI_0_rid,
    output logic        S00_AXI_0_rlast,
    input  logic        S00_AXI_0_rready,
    output logic [1:0]  S00_AXI_0_rresp,
    output logic        S00_AXI_0_rvalid,
    input  logic [63:0] S00_AXI_0_wdata,
    input  logic        S00_AXI_0_wlast,
    output logic        S00_AXI_0_wready,
    input  logic [7:0]  S00_AXI_0_wstrb,
    input  logic        S00_AXI_0_wvalid,
    `HBM_SIM_UNUSED_CHANNEL(S01)
    `HBM_SIM_UNUSED_CHANNEL(S02)
    `HBM_SIM_UNUSED_CHANNEL(S03)
    `HBM_SIM_UNUSED_CHANNEL(S04)
    `HBM_SIM_UNUSED_CHANNEL(S05)
    `HBM_SIM_UNUSED_CHANNEL(S06)
    `HBM_SIM_UNUSED_CHANNEL(S07)
    `HBM_SIM_UNUSED_CHANNEL(S08)
    `HBM_SIM_UNUSED_CHANNEL(S09)
    `HBM_SIM_UNUSED_CHANNEL(S10)
    `HBM_SIM_UNUSED_CHANNEL(S11)
    input  logic [15:0] pcie_mgt_0_rxn,
    input  logic [15:0] pcie_mgt_0_rxp,
    output logic [15:0] pcie_mgt_0_txn,
    output logic [15:0] pcie_mgt_0_txp,
    input  logic        sys_clk_0,
    input  logic        sys_clk_gt_0,
    input  logic        sys_rst_n_0,
    input  logic [0:0]  usr_irq_req_0,
    output logic        master_areset_o_0
);

    logic clk;
    assign clk = axi_clk_cluster_S00;

    assign pcie_mgt_0_txn    = '0;
    assign pcie_mgt_0_txp    = '0;
    assign master_areset_o_0 = 1'b0;

    `HBM_SIM_UNUSED_CHANNEL_TIE(S01)
    `HBM_SIM_UNUSED_CHANNEL_TIE(S02)
    `HBM_SIM_UNUSED_CHANNEL_TIE(S03)
    `HBM_SIM_UNUSED_CHANNEL_TIE(S04)
    `HBM_SIM_UNUSED_CHANNEL_TIE(S05)
    `HBM_SIM_UNUSED_CHANNEL_TIE(S06)
    `HBM_SIM_UNUSED_CHANNEL_TIE(S07)
    `HBM_SIM_UNUSED_CHANNEL_TIE(S08)
    `HBM_SIM_UNUSED_CHANNEL_TIE(S09)
    `HBM_SIM_UNUSED_CHANNEL_TIE(S10)
    `HBM_SIM_UNUSED_CHANNEL_TIE(S11)

    // sparse: the whole 16GB HBM address space, bytes never written read as 0
    bit [7:0] mem [bit [33:0]];

    initial begin
        string hex;
        if ($value$plusargs("DRAM_HEX=%s", hex)) begin
            $display("[hbm_interface] loading %s", hex);
            $readmemh(hex, mem);
        end
    end

    function automatic logic [33:0] next_addr(logic [33:0] addr, logic [2:0] size, logic [1:0] burst);
        return (burst == axi_pkg::BURST_FIXED) ? addr : addr + (34'd1 << size);
    endfunction

    // -----------------
    // read channel
    // -----------------
    logic        rd_busy;
    logic [33:0] rd_addr;
    logic [7:0]  rd_len;
    logic [2:0]  rd_size;
    logic [1:0]  rd_burst;

    assign S00_AXI_0_arready = ~rd_busy;
    assign S00_AXI_0_rvalid  = rd_busy;
    assign S00_AXI_0_rlast   = rd_busy && (rd_len == '0);
    assign S00_AXI_0_rresp   = axi_pkg::RESP_OKAY;
    always_comb begin
        for (int b = 0; b < 8; b++) begin
            logic [33:0] a;
            a = (rd_addr & ~34'h7) + b;
            S00_AXI_0_rdata[8*b +: 8] = mem.exists(a) ? mem[a] : 8'h00;
        end
    end

    always_ff @(posedge clk or negedge sys_rst_n_0) begin
        if (!sys_rst_n_0) begin
            rd_busy <= 1'b0;
        end else if (!rd_busy) begin
            if (S00_AXI_0_arvalid) begin
                rd_busy        <= 1'b1;
                rd_addr        <= S00_AXI_0_araddr;
                rd_len         <= S00_AXI_0_arlen;
                rd_size        <= S00_AXI_0_arsize;
                rd_burst       <= S00_AXI_0_arburst;
                S00_AXI_0_rid  <= S00_AXI_0_arid;
            end
        end else if (S00_AXI_0_rready) begin
            rd_addr <= next_addr(rd_addr, rd_size, rd_burst);
            rd_len  <= rd_len - 1;
            if (rd_len == '0) rd_busy <= 1'b0;
        end
    end

    // -----------------
    // write channel
    // -----------------
    logic        wr_busy;
    logic [33:0] wr_addr;
    logic [2:0]  wr_size;
    logic [1:0]  wr_burst;

    assign S00_AXI_0_awready = ~wr_busy & ~S00_AXI_0_bvalid;
    assign S00_AXI_0_wready  = wr_busy;
    assign S00_AXI_0_bresp   = axi_pkg::RESP_OKAY;

    always_ff @(posedge clk or negedge sys_rst_n_0) begin
        if (!sys_rst_n_0) begin
            wr_busy          <= 1'b0;
            S00_AXI_0_bvalid <= 1'b0;
        end else begin
            if (S00_AXI_0_bvalid && S00_AXI_0_bready) S00_AXI_0_bvalid <= 1'b0;
            if (!wr_busy) begin
                if (S00_AXI_0_awvalid && S00_AXI_0_awready) begin
                    wr_busy       <= 1'b1;
                    wr_addr       <= S00_AXI_0_awaddr;
                    wr_size       <= S00_AXI_0_awsize;
                    wr_burst      <= S00_AXI_0_awburst;
                    S00_AXI_0_bid <= S00_AXI_0_awid;
                end
            end else if (S00_AXI_0_wvalid) begin
                for (int b = 0; b < 8; b++)
                    // blocking: associative array element (read and write channels are independent)
                    if (S00_AXI_0_wstrb[b]) mem[(wr_addr & ~34'h7) + b] = S00_AXI_0_wdata[8*b +: 8];
                wr_addr <= next_addr(wr_addr, wr_size, wr_burst);
                if (S00_AXI_0_wlast) begin
                    wr_busy          <= 1'b0;
                    S00_AXI_0_bvalid <= 1'b1;
                end
            end
        end
    end

endmodule
