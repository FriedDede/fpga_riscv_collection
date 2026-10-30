// Copyright 2024 Politecnico di Milano.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

// Description: simulation models of the clock wizards of tcl_scripts/gen_clock.tcl.
//              The outputs are free running with unrelated periods, to exercise the clock
//              domain crossings. periph_clk is 50 MHz: the bootrom uart divisor
//              (bootrom_u55/src/platform.h) and the tb_veer uart decoder assume it.
//              locked rises a few clk_in1 cycles after reset.
// Author: Andrea Motta

`timescale 1ns/1ps

module xlnx_clk_gen_sim_osc #(
    parameter realtime Period = 10ns,
    parameter realtime Phase  = 0ns
)(
    output logic clk_o
);
    initial begin
        clk_o = 1'b0;
        #(Phase);
        forever #(Period / 2) clk_o = ~clk_o;
    end
endmodule

module xlnx_clk_gen_sim_lock (
    input  logic clk_in1,
    input  logic reset,
    output logic locked
);
    logic [3:0] lock_cnt;
    always_ff @(posedge clk_in1 or posedge reset) begin
        if (reset) begin
            lock_cnt <= '0;
            locked   <= 1'b0;
        end else if (lock_cnt != '1) begin
            lock_cnt <= lock_cnt + 1;
        end else begin
            locked   <= 1'b1;
        end
    end
endmodule

// cluster clock + 6 core clocks
module xlnx_clk_gen_cluster #(
    parameter realtime ClusterPeriod = 16ns,    // 62.5 MHz
    parameter realtime CorePeriod    = 13ns     // ~77 MHz
)(
    output logic cluster_clk,
    output logic core_clk_0,
    output logic core_clk_1,
    output logic core_clk_2,
    output logic core_clk_3,
    output logic core_clk_4,
    output logic core_clk_5,
    input  logic reset,
    output logic locked,
    input  logic clk_in1
);
    xlnx_clk_gen_sim_osc #(.Period(ClusterPeriod), .Phase(1.3ns)) i_cluster (.clk_o(cluster_clk));
    xlnx_clk_gen_sim_osc #(.Period(CorePeriod),    .Phase(0.0ns)) i_core_0  (.clk_o(core_clk_0));
    xlnx_clk_gen_sim_osc #(.Period(CorePeriod),    .Phase(0.5ns)) i_core_1  (.clk_o(core_clk_1));
    xlnx_clk_gen_sim_osc #(.Period(CorePeriod),    .Phase(1.0ns)) i_core_2  (.clk_o(core_clk_2));
    xlnx_clk_gen_sim_osc #(.Period(CorePeriod),    .Phase(1.5ns)) i_core_3  (.clk_o(core_clk_3));
    xlnx_clk_gen_sim_osc #(.Period(CorePeriod),    .Phase(2.0ns)) i_core_4  (.clk_o(core_clk_4));
    xlnx_clk_gen_sim_osc #(.Period(CorePeriod),    .Phase(2.5ns)) i_core_5  (.clk_o(core_clk_5));
    xlnx_clk_gen_sim_lock i_lock (.clk_in1, .reset, .locked);
endmodule

// peripheral clock
module xlnx_clk_gen_periph #(
    parameter realtime PeriphPeriod = 20ns      // 50 MHz
)(
    output logic periph_clk,
    input  logic reset,
    output logic locked,
    input  logic clk_in1
);
    xlnx_clk_gen_sim_osc #(.Period(PeriphPeriod), .Phase(2.7ns)) i_periph (.clk_o(periph_clk));
    xlnx_clk_gen_sim_lock i_lock (.clk_in1, .reset, .locked);
endmodule
