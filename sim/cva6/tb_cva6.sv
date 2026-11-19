// Copyright 2024 Politecnico di Milano.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

// Description: testbench of the CVA6 u55c top (hw/cluster/tops/u55_cva6_top.sv). The FPGA top is
//              simulated as is, hbm_interface and the clock wizards are replaced by models.
//              The payload in DRAM (+DRAM_HEX) reports its result writing TOHOST:
//              1 = pass, any other value = fail. UART output is printed on the console.
// Author: Andrea Motta

`timescale 1ns/1ps

module tb_cva6;

    localparam time         CLOCK_PERIOD = 10ns;     // 100 MHz board clocks
    localparam time         UART_BIT     = 8640ns;   // 50 MHz / (16 * 27), init_uart(50MHz, 115200)
    localparam int unsigned TOHOST       = 32'h0000_1000; // DRAM 0x8000_1000, HBM address
    localparam longint      MAX_CYCLES   = 5_000_000;

    logic clk;
    logic rst_n;
    logic uart_rx;
    logic uart_tx;

    cva6_u55_xilinx_bd dut (
        .sys_clk_p      (clk),
        .sys_clk_n      (~clk),
        .prst_n         (rst_n),
        .HBM_ref_clk_p  (clk),
        .HBM_ref_clk_n  (~clk),
        .hbm_cattrip    (),
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

    // +trace_axi: print the requests of the core (cluster side of its axi_cdc)
    `define CVA6_AXI dut.cluster_gen[0].axi_cva2xbar[0]
    bit trace_axi;
    initial trace_axi = $test$plusargs("trace_axi");
    always @(posedge dut.clk_cluster[0]) begin
        if (trace_axi && `CVA6_AXI.ar_valid && `CVA6_AXI.ar_ready)
            $display("[tb_cva6] %t AR id %0d addr 0x%08h len %0d size %0d burst %0d", $time, `CVA6_AXI.ar_id,
                     `CVA6_AXI.ar_addr, `CVA6_AXI.ar_len, `CVA6_AXI.ar_size, `CVA6_AXI.ar_burst);
        if (trace_axi && `CVA6_AXI.r_valid && `CVA6_AXI.r_ready)
            $display("[tb_cva6] %t R  id %0d data 0x%016h last %0d resp %0d", $time, `CVA6_AXI.r_id,
                     `CVA6_AXI.r_data, `CVA6_AXI.r_last, `CVA6_AXI.r_resp);
        if (trace_axi && `CVA6_AXI.aw_valid && `CVA6_AXI.aw_ready)
            $display("[tb_cva6] %t AW id %0d addr 0x%08h len %0d size %0d atop %0d", $time, `CVA6_AXI.aw_id,
                     `CVA6_AXI.aw_addr, `CVA6_AXI.aw_len, `CVA6_AXI.aw_size, `CVA6_AXI.aw_atop);
    end

    // stop at the first exception, the bootrom trap handler spins forever
    `define CVA6 dut.cluster_gen[0].core_gen[0].i_cva6.cva6_instance
    always @(posedge dut.clk_core[0][0]) begin
        if (`CVA6.rst_ni && `CVA6.ex_commit.valid) begin
            $display("\n[tb_cva6] FAIL: exception at pc 0x%016h, mcause %0d, mtval 0x%016h",
                     `CVA6.pc_commit, `CVA6.ex_commit.cause, `CVA6.ex_commit.tval);
            $finish;
        end
    end

    initial begin
        static longint cycles = 0;
        logic [31:0] tohost;
        @(posedge rst_n);
        forever begin
            @(posedge dut.clk_cluster[0]);
            cycles++;
            tohost = read_tohost();
            if (tohost != '0) begin
                $display("\n[tb_cva6] tohost = 0x%08h after %0d cluster cycles: %s", tohost, cycles,
                         tohost == 32'h1 ? "PASS" : "FAIL");
                $finish;
            end
            if (cycles == MAX_CYCLES) begin
                $display("\n[tb_cva6] TIMEOUT after %0d cluster cycles, commit pc 0x%016h", cycles, `CVA6.pc_commit);
                $finish;
            end
        end
    end

endmodule
