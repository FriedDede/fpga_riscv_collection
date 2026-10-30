// Copyright 2024 Politecnico di Milano.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

// Description: testbench of the VeeR u55c top (hw/cluster/tops/u55_VeeR_top.sv). The FPGA top is
//              simulated as is, hbm_interface and the clock wizards are replaced by models.
//              The payload in DRAM (+DRAM_HEX) reports its result writing TOHOST:
//              1 = pass, any other value = fail. UART output is printed on the console.
// Author: Andrea Motta

`timescale 1ns/1ps

module tb_veer;

    localparam time         CLOCK_PERIOD = 10ns;     // 100 MHz board clocks
    localparam time         UART_BIT     = 8640ns;   // 50 MHz / (16 * 27), init_uart(50MHz, 115200)
    localparam int unsigned TOHOST       = 32'h0000_1000; // DRAM 0x8000_1000, HBM address
    localparam longint      MAX_CYCLES   = 5_000_000;

    logic clk;
    logic rst_n;
    logic uart_rx;
    logic uart_tx;

    veer_u55_xilinx_bd dut (
        .sys_clk_p      (clk),
        .sys_clk_n      (~clk),
        .prst_n         (rst_n),
        .HBM_ref_clk_p  (clk),
        .HBM_ref_clk_n  (~clk),
        .pcie_x16_txp   (),
        .pcie_x16_txn   (),
        .pcie_x16_rxp   ('0),
        .pcie_x16_rxn   ('1),
        .uart_rx        (uart_rx),
        .uart_tx        (uart_tx)
    );

    assign uart_rx = 1'b1;

    initial begin
        clk = 1'b0;
        forever #(CLOCK_PERIOD/2) clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        repeat (100) @(posedge clk);
        rst_n = 1'b1;
    end

    // -----------------
    // UART console
    // -----------------
    initial begin
        logic [7:0] char;
        @(posedge dut.rst_periph_n);
        forever begin
            @(negedge uart_tx);
            #(UART_BIT * 3 / 2);
            for (int i = 0; i < 8; i++) begin
                char[i] = uart_tx;
                #(UART_BIT);
            end
            $write("%c", char);
        end
    end

    // -----------------
    // end of test
    // -----------------
    function automatic logic [31:0] read_tohost();
        for (int b = 0; b < 4; b++) read_tohost[8*b +: 8] = dut.i_hbm_interface.mem[TOHOST + b];
    endfunction

    // stop at the first exception, the bootrom trap handler spins forever
    `define VEER dut.cluster_gen[0].core_gen[0].i_veer.veer_instance
    always @(posedge dut.clk_core[0][0]) begin
        if (`VEER.trace_rv_i_valid_ip && `VEER.trace_rv_i_exception_ip) begin
            $display("\n[tb_veer] FAIL: exception at pc 0x%08h, insn 0x%08h, mcause %0d, mtval 0x%08h",
                     `VEER.trace_rv_i_address_ip, `VEER.trace_rv_i_insn_ip,
                     `VEER.trace_rv_i_ecause_ip, `VEER.trace_rv_i_tval_ip);
            $finish;
        end
    end

    initial begin
        longint cycles = 0;
        logic [31:0] tohost;
        @(posedge rst_n);
        forever begin
            @(posedge dut.clk_cluster[0]);
            cycles++;
            tohost = read_tohost();
            if (tohost != '0) begin
                $display("\n[tb_veer] tohost = 0x%08h after %0d cluster cycles: %s", tohost, cycles,
                         tohost == 32'h1 ? "PASS" : "FAIL");
                $finish;
            end
            if (cycles == MAX_CYCLES) begin
                $display("\n[tb_veer] TIMEOUT after %0d cluster cycles, last retired pc 0x%08h", cycles,
                         `VEER.trace_rv_i_address_ip);
                $finish;
            end
        end
    end

endmodule
