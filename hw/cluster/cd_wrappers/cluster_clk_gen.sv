// Copyright 2024 Politecnico di Milano.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

// Description: clock generator of one cluster (one MMCM, xlnx_clk_gen_cluster in
//              tcl_scripts/gen_clock.tcl): the cluster crossbar clock and one clock per core,
//              all asynchronous to each other. Up to 6 cores per cluster.
// Author: Andrea Motta

module cluster_clk_gen #(
    parameter int unsigned NumCores = 1
)(
    input  logic                clk_in1,        // 100 MHz reference
    input  logic                reset,          // active high
    output logic                locked,
    output logic                clk_cluster_o,
    output logic [NumCores-1:0] clk_core_o
);

    localparam int unsigned MaxCores = 6;   // 7 MMCM outputs, one is the cluster clock

    if (NumCores > MaxCores) begin : gen_too_many_cores
        $error("cluster_clk_gen: %0d cores, at most %0d per cluster", NumCores, MaxCores);
    end

    logic [MaxCores-1:0] clk_core;

    xlnx_clk_gen_cluster i_clk_gen (
        .cluster_clk ( clk_cluster_o ),
        .core_clk_0  ( clk_core[0]   ),
        .core_clk_1  ( clk_core[1]   ),
        .core_clk_2  ( clk_core[2]   ),
        .core_clk_3  ( clk_core[3]   ),
        .core_clk_4  ( clk_core[4]   ),
        .core_clk_5  ( clk_core[5]   ),
        .reset       ( reset         ),
        .locked      ( locked        ),
        .clk_in1     ( clk_in1       )
    );

    assign clk_core_o = clk_core[NumCores-1:0];

endmodule
