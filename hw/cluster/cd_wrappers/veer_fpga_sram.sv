// Copyright 2024 Politecnico di Milano.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

// Description: single port sram, same protocol as the VeeR ram_<depth>x<width> macros
//              (1 cycle read latency, read data kept on write), infers no-change BRAM
// Author: Andrea Motta

module veer_fpga_sram #(
    parameter int unsigned Depth = 4096,
    parameter int unsigned Width = 39
)(
    input  logic                     clk_i,
    input  logic                     me_i,      // memory enable
    input  logic                     we_i,      // write enable (when me_i)
    input  logic [$clog2(Depth)-1:0] addr_i,
    input  logic [Width-1:0]         wdata_i,
    output logic [Width-1:0]         rdata_o
);

    (* ram_style = "block" *) logic [Width-1:0] mem [Depth];

    // zero init: all-zero is a valid ECC codeword, uninitialized reads do not raise ECC errors
    initial begin
        for (int i = 0; i < Depth; i++) mem[i] = '0;
    end

    always_ff @(posedge clk_i) begin
        if (me_i) begin
            if (we_i) mem[addr_i] <= wdata_i;
            else      rdata_o     <= mem[addr_i];
        end
    end

endmodule
