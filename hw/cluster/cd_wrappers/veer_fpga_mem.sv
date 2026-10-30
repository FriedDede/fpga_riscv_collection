// Copyright 2024 Politecnico di Milano.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

// Description: VeeR-EL2 DCCM, ICCM and I$ (data + tag) memories for FPGA.
//              Sink side of el2_mem_if, replaces the sram instances of the VeeR tb_top.
//              Requires a snapshot with icache_waypack=0 (one sram per way, no bit enables).
// Author: Andrea Motta

module veer_fpga_mem
    import el2_pkg::*;
#(
`include "el2_param.vh"
)(
    el2_mem_if mem_export
);

    localparam int IcDataWidth = pt.ICACHE_ECC ? 71 : 68;

// -----------------
// DCCM
// -----------------
    if (pt.DCCM_ENABLE) begin : gen_dccm
        for (genvar b = 0; b < pt.DCCM_NUM_BANKS; ++b) begin : gen_bank
            logic [pt.DCCM_FDATA_WIDTH-1:0] rdata;
            veer_fpga_sram #(
                .Depth  (2**pt.DCCM_INDEX_BITS),
                .Width  (pt.DCCM_FDATA_WIDTH)
            ) i_dccm_bank (
                .clk_i  (mem_export.clk),
                .me_i   (mem_export.dccm_clken[b]),
                .we_i   (mem_export.dccm_wren_bank[b]),
                .addr_i (mem_export.dccm_addr_bank[b]),
                .wdata_i({mem_export.dccm_wr_ecc_bank[b], mem_export.dccm_wr_data_bank[b]}),
                .rdata_o(rdata)
            );
            assign mem_export.dccm_bank_dout[b] = rdata[pt.DCCM_DATA_WIDTH-1:0];
            assign mem_export.dccm_bank_ecc[b]  = rdata[pt.DCCM_FDATA_WIDTH-1:pt.DCCM_DATA_WIDTH];
        end : gen_bank
    end else begin : gen_no_dccm
        assign mem_export.dccm_bank_dout = '0;
        assign mem_export.dccm_bank_ecc  = '0;
    end

// -----------------
// ICCM
// -----------------
    if (pt.ICCM_ENABLE) begin : gen_iccm
        for (genvar b = 0; b < pt.ICCM_NUM_BANKS; ++b) begin : gen_bank
            logic [32+pt.ICCM_ECC_WIDTH-1:0] rdata;
            veer_fpga_sram #(
                .Depth  (2**pt.ICCM_INDEX_BITS),
                .Width  (32 + pt.ICCM_ECC_WIDTH)
            ) i_iccm_bank (
                .clk_i  (mem_export.clk),
                .me_i   (mem_export.iccm_clken[b]),
                .we_i   (mem_export.iccm_wren_bank[b]),
                .addr_i (mem_export.iccm_addr_bank[b]),
                .wdata_i({mem_export.iccm_bank_wr_ecc[b], mem_export.iccm_bank_wr_data[b]}),
                .rdata_o(rdata)
            );
            assign mem_export.iccm_bank_dout[b] = rdata[31:0];
            assign mem_export.iccm_bank_ecc[b]  = rdata[32+pt.ICCM_ECC_WIDTH-1:32];
        end : gen_bank
    end else begin : gen_no_iccm
        assign mem_export.iccm_bank_dout = '0;
        assign mem_export.iccm_bank_ecc  = '0;
    end

// -----------------
// ICACHE
// -----------------
    // way packed srams are not used
    assign mem_export.wb_packeddout_pre          = '0;
    assign mem_export.ic_tag_data_raw_packed_pre = '0;

    if (pt.ICACHE_ENABLE) begin : gen_icache
        for (genvar w = 0; w < pt.ICACHE_NUM_WAYS; ++w) begin : gen_way
            // data: one sram per way per bank
            for (genvar k = 0; k < pt.ICACHE_BANKS_WAY; ++k) begin : gen_bank
                logic [IcDataWidth-1:0] rdata;
                veer_fpga_sram #(
                    .Depth  (pt.ICACHE_DATA_DEPTH),
                    .Width  (IcDataWidth)
                ) i_ic_data (
                    .clk_i  (mem_export.clk),
                    .me_i   (mem_export.ic_bank_way_clken_final_up[w][k]),
                    .we_i   (mem_export.ic_b_sb_wren[k][w]),
                    .addr_i (mem_export.ic_rw_addr_bank_q[k][pt.ICACHE_INDEX_HI:pt.ICACHE_DATA_INDEX_LO]),
                    .wdata_i(mem_export.ic_sb_wr_data[k][IcDataWidth-1:0]),
                    .rdata_o(rdata)
                );
                assign mem_export.wb_dout_pre_up[w][k] = 71'(rdata);
            end : gen_bank
            // tag
            veer_fpga_sram #(
                .Depth  (pt.ICACHE_TAG_DEPTH),
                .Width  (26)
            ) i_ic_tag (
                .clk_i  (mem_export.clk),
                .me_i   (mem_export.ic_tag_clken_final[w]),
                .we_i   (mem_export.ic_tag_wren_q[w]),
                .addr_i (mem_export.ic_rw_addr_q[pt.ICACHE_INDEX_HI:pt.ICACHE_TAG_INDEX_LO]),
                .wdata_i(mem_export.ic_tag_wr_data),
                .rdata_o(mem_export.ic_tag_data_raw_pre[w])
            );
        end : gen_way
    end else begin : gen_no_icache
        assign mem_export.wb_dout_pre_up      = '0;
        assign mem_export.ic_tag_data_raw_pre = '0;
    end

endmodule
