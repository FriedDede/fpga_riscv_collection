/* Copyright 2018 ETH Zurich and University of Bologna.
 * Copyright and related rights are licensed under the Solderpad Hardware
 * License, Version 0.51 (the "License"); you may not use this file except in
 * compliance with the License.  You may obtain a copy of the License at
 * http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
 * or agreed to in writing, software, hardware and materials distributed under
 * this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 * CONDITIONS OF ANY KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations under the License.
 *
 * File: $filename.v
 *
 * Description: Auto-generated bootrom
 */

// Auto-generated code
// 29/08/2024 10:50:34
module bootrom (
   input  logic         clk_i,
   input  logic         req_i,
   input  logic [63:0]  addr_i,
   output logic [63:0]  rdata_o,
   output logic         rvalid_o
);
    localparam int RomSize = 129;

    const logic [RomSize-1:0][63:0] mem = {
        64'h3f800000_00000000,
        64'h00000000_00000000,
        64'h00000000_00000000,
        64'h00000000_00000000,
        64'h00000000_00000000,
        64'h00000000_00000000,
        64'h00000000_00000000,
        64'h00000000_00000000,
        64'h00000000_00000000,
        64'h00000000_00000000,
        64'h00000000_00000000,
        64'h00000000_00000000,
        64'h00000000_00000000,
        64'h00000000_00000000,
        64'h00000000_00000000,
        64'h00000000_00000000,
        64'h00000000_00000000,
        64'h00000000_00000000,
        64'h00000000_00000000,
        64'h00000000_00000000,
        64'h00000000_00000000,
        64'h0000006f_000400e7,
        64'h80010437_fee792e3,
        64'h00e7f7d3_0cc6a707,
        64'hfee7ae27_10f77753,
        64'h00478793_00000697,
        64'h0007a707_40078713,
        64'h800007b7_f00007d3,
        64'hfed798e3_00178793,
        64'h00f72023_00e60733,
        64'h00279713_10000693,
        64'h80000637_00000793,
        64'h0000006f_00000000,
        64'h00000000_00000000,
        64'h00000000_00000000,
        64'h00000000_00000000,
        64'h00000000_00000000,
        64'h00000000_00000000,
        64'h00000000_00000000,
        64'h00000000_00000000,
        64'h00000000_00000000,
        64'h00000000_00000000,
        64'h00000000_00000000,
        64'h00000000_00000000,
        64'h00000000_00000000,
        64'h00000000_00000000,
        64'h00000000_00000000,
        64'h00048067_800004b7,
        64'hf1402573_ff24c6e3,
        64'h40090913_02000937,
        64'h00448493_fe091ee3,
        64'h0004a903_00092023,
        64'h00990933_00291913,
        64'hf1402973_020004b7,
        64'hfe090ae3_00897913,
        64'h34402973_10500073,
        64'hff24c6e3_40090913,
        64'h02000937_00448493,
        64'h0124a023_00100913,
        64'h020004b7_0e0000ef,
        64'ha0000137_30529073,
        64'h0ec28293_00000297,
        64'h03249a63_f1402973,
        64'h00000493_30491073
    };

    logic [$clog2(RomSize)-1:0] addr_q;

    always_ff @(posedge clk_i) begin
        if (req_i) begin
            addr_q <= addr_i[$clog2(RomSize)-1+3:3];
            rvalid_o <= 1;
        end else begin
            rvalid_o <= 0;
        end
    end

    // this prevents spurious Xes from propagating into
    // the speculative fetch stage of the core
    assign rdata_o = (addr_q < RomSize) ? mem[addr_q] : '0;
endmodule
