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
// 19/08/2024 11:26:24
module bootrom (
   input  logic         clk_i,
   input  logic         req_i,
   input  logic [63:0]  addr_i,
   output logic [63:0]  rdata_o,
   output logic         rvalid_o
);
    localparam int RomSize = 68;

    const logic [RomSize-1:0][63:0] mem = {
        64'h0000006f_000400e7,
        64'h80010437_0000006f,
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
        64'h00000000_00048067,
        64'h800004b7_f1402573,
        64'hff24c6e3_40090913,
        64'h02000937_00448493,
        64'hfe091ee3_0004a903,
        64'h00092023_00990933,
        64'h00291913_f1402973,
        64'h020004b7_fe090ae3,
        64'h00897913_34402973,
        64'h10500073_ff24c6e3,
        64'h40090913_02000937,
        64'h00448493_0124a023,
        64'h00100913_020004b7,
        64'h0e0000ef_a0000137,
        64'h30529073_0ec28293,
        64'h00000297_03249a63,
        64'hf1402973_00000493,
        64'h30491073_00800913
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
