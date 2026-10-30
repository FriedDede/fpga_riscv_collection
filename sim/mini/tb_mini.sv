// Copyright 2024 Politecnico di Milano.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

// Description: testbench of the riscv-mini u55c top (hw/cluster/tops/u55_mini_top.sv). The
//              FPGA top is simulated as is, hbm_interface and the clock wizards are replaced
//              by models (sim/models). The payload in DRAM (+DRAM_HEX) reports its result in
//              the mtohost csr (the D$ is write-back): 1 = pass, any other value = fail.
//              A fetch of the machine mode trap vector (0x1c0) ends the test as failed.
// Author: Andrea Motta

`timescale 1ns/1ps

module tb_mini;

    localparam time    CLOCK_PERIOD = 10ns;     // 100 MHz board clocks
    localparam longint MAX_CYCLES   = 2_000_000;

    logic clk;
    logic rst_n;

    mini_u55_xilinx_bd dut (
        .sys_clk_p      (clk),
        .sys_clk_n      (~clk),
        .prst_n         (rst_n),
        .HBM_ref_clk_p  (clk),
        .HBM_ref_clk_n  (~clk),
        .pcie_x16_txp   (),
        .pcie_x16_txn   (),
        .pcie_x16_rxp   ('0),
        .pcie_x16_rxn   ('1),
        .uart_rx        (1'b1),
        .uart_tx        ()
    );

    initial begin
        clk = 1'b0;
        forever #(CLOCK_PERIOD/2) clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        repeat (100) @(posedge clk);
        rst_n = 1'b1;
    end

    `define MINI dut.cluster_gen[0].core_gen[0].i_mini.i_tile

    // +trace_axi: print the requests of the core (cluster side of its axi_cdc)
    `define MINI_AXI dut.cluster_gen[0].axi_mini2xbar[0]
    bit trace_axi;
    initial trace_axi = $test$plusargs("trace_axi");
    always @(posedge dut.clk_cluster[0]) begin
        if (trace_axi && `MINI_AXI.ar_valid && `MINI_AXI.ar_ready)
            $display("[tb_mini] %t AR addr 0x%08h len %0d size %0d", $time, `MINI_AXI.ar_addr, `MINI_AXI.ar_len, `MINI_AXI.ar_size);
        if (trace_axi && `MINI_AXI.aw_valid && `MINI_AXI.aw_ready)
            $display("[tb_mini] %t AW addr 0x%08h len %0d size %0d", $time, `MINI_AXI.aw_addr, `MINI_AXI.aw_len, `MINI_AXI.aw_size);
        if (trace_axi && `MINI_AXI.r_valid && `MINI_AXI.r_ready)
            $display("[tb_mini] %t R  data 0x%016h last %0d resp %0d", $time, `MINI_AXI.r_data, `MINI_AXI.r_last, `MINI_AXI.r_resp);
    end

    // +trace_pc: print the pc of the instructions in the execute/writeback stage
    bit trace_pc;
    logic [31:0] last_pc;
    initial trace_pc = $test$plusargs("trace_pc");
    always @(posedge dut.clk_core[0][0]) begin
        if (trace_pc && `MINI.core.dpath.ew_reg_pc != last_pc)
            $display("[tb_mini] %t pc 0x%08h inst 0x%08h", $time, `MINI.core.dpath.ew_reg_pc, `MINI.core.dpath.ew_reg_inst);
        last_pc <= `MINI.core.dpath.ew_reg_pc;
    end

    // the bootrom trap handler spins forever: stop at the first fetch of the trap vector
    always @(posedge dut.clk_cluster[0]) begin
        if (dut.cluster_gen[0].axi_rom.ar_valid && dut.cluster_gen[0].axi_rom.ar_ready &&
            dut.cluster_gen[0].axi_rom.ar_addr[15:4] == 12'h01c) begin
            $display("\n[tb_mini] FAIL: trap (fetch of the trap vector 0x1c0)");
            $finish;
        end
    end

    initial begin
        longint cycles = 0;
        @(posedge rst_n);
        forever begin
            @(posedge dut.clk_cluster[0]);
            cycles++;
            if (`MINI.io_host_tohost != '0) begin
                $display("\n[tb_mini] tohost = 0x%08h after %0d cluster cycles: %s", `MINI.io_host_tohost,
                         cycles, `MINI.io_host_tohost == 32'h1 ? "PASS" : "FAIL");
                $finish;
            end
            if (cycles == MAX_CYCLES) begin
                $display("\n[tb_mini] TIMEOUT after %0d cluster cycles", cycles);
                $finish;
            end
        end
    end

endmodule
