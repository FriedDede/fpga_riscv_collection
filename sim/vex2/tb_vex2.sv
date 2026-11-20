// Copyright 2024 Politecnico di Milano.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

// Description: testbench of the VexiiRiscv u55c top (hw/cluster/tops/u55_vex2_top.sv). The FPGA top is
//              simulated as is, hbm_interface and the clock wizards are replaced by models.
//              The payload in DRAM (+DRAM_HEX) reports its result writing TOHOST:
//              1 = pass, any other value = fail. UART output is printed on the console.
// Author: Andrea Motta

`timescale 1ns/1ps

module tb_vex2;

    localparam time         CLOCK_PERIOD = 10ns;     // 100 MHz board clocks
    localparam time         UART_BIT     = 8640ns;   // 50 MHz / (16 * 27), init_uart(50MHz, 115200)
    localparam int unsigned TOHOST       = 32'h0000_1000; // DRAM 0x8000_1000, HBM address
    longint                 MAX_CYCLES   = 5_000_000;  // cluster cycles, +MAX_CYCLES=<n>
    initial void'($value$plusargs("MAX_CYCLES=%d", MAX_CYCLES));

    logic clk;
    logic rst_n;
    logic uart_rx;
    logic uart_tx;

    vex2_u55_xilinx_bd dut (
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

    `define VEX dut.cluster_gen[0].core_gen[0].i_vex.i_vex
    `define TRAP(sig) `VEX.TrapPlugin_logic_harts_0_trap_``sig

    // +trace_axi: print the requests of the core (cluster side of its axi_cdc)
    bit trace_axi;
    initial trace_axi = $test$plusargs("trace_axi");
    localparam string PortName [3] = '{"ibus ", "dbus ", "iobus"};
    for (genvar k = 0; k < 3; k++) begin : gen_trace
        always @(posedge dut.clk_cluster[0]) begin
            if (trace_axi && dut.cluster_gen[0].axi_vex2xbar[k].ar_valid && dut.cluster_gen[0].axi_vex2xbar[k].ar_ready)
                $display("[tb_vex2] %t %s AR addr 0x%08h len %0d size %0d", $time, PortName[k],
                         dut.cluster_gen[0].axi_vex2xbar[k].ar_addr, dut.cluster_gen[0].axi_vex2xbar[k].ar_len,
                         dut.cluster_gen[0].axi_vex2xbar[k].ar_size);
            if (trace_axi && dut.cluster_gen[0].axi_vex2xbar[k].aw_valid && dut.cluster_gen[0].axi_vex2xbar[k].aw_ready)
                $display("[tb_vex2] %t %s AW addr 0x%08h len %0d size %0d", $time, PortName[k],
                         dut.cluster_gen[0].axi_vex2xbar[k].aw_addr, dut.cluster_gen[0].axi_vex2xbar[k].aw_len,
                         dut.cluster_gen[0].axi_vex2xbar[k].aw_size);
            if (trace_axi && dut.cluster_gen[0].axi_vex2xbar[k].w_valid && dut.cluster_gen[0].axi_vex2xbar[k].w_ready)
                $display("[tb_vex2] %t %s W  data 0x%016h strb 0x%02h last %0d", $time, PortName[k],
                         dut.cluster_gen[0].axi_vex2xbar[k].w_data, dut.cluster_gen[0].axi_vex2xbar[k].w_strb,
                         dut.cluster_gen[0].axi_vex2xbar[k].w_last);
            if (trace_axi && dut.cluster_gen[0].axi_vex2xbar[k].r_valid && dut.cluster_gen[0].axi_vex2xbar[k].r_ready)
                $display("[tb_vex2] %t %s R  data 0x%016h last %0d resp %0d", $time, PortName[k],
                         dut.cluster_gen[0].axi_vex2xbar[k].r_data, dut.cluster_gen[0].axi_vex2xbar[k].r_last,
                         dut.cluster_gen[0].axi_vex2xbar[k].r_resp);
        end
    end

    // stop at the first trap to the bootrom trap handler (it spins forever): the payload installs its
    // own mtvec for the traps it expects. The trap fsm jumps to mtvec in TRAP_APPLY
    localparam logic [3:0] TrapApply = 4'd9;   // TrapPlugin_logic_harts_0_trap_fsm_TRAP_APPLY
    always @(posedge dut.clk_core[0][0]) begin
        if (dut.cluster_gen[0].core_gen[0].i_vex.rst_core_n === 1'b1 &&
            `TRAP(fsm_stateReg) == TrapApply && `TRAP(pcPort_valid) &&
            `TRAP(pcPort_payload_pc) < 32'h0001_0000) begin
            $display("\n[tb_vex2] FAIL: trap at pc 0x%08h, mcause %0d (interrupt %0d), mtval 0x%08h",
                     `TRAP(pending_pc), `TRAP(fsm_buffer_trap_code),
                     `TRAP(fsm_buffer_trap_interrupt), `TRAP(fsm_buffer_trap_tval));
            $finish;
        end
    end

    // last committed pc (timeout report)
    logic [31:0] last_pc = '0;
    always @(posedge dut.clk_core[0][0])
        if (`VEX.WhiteboxerPlugin_logic_commits_ports_0_valid) last_pc <= `VEX.WhiteboxerPlugin_logic_commits_ports_0_pc;

    initial begin
        static longint cycles = 0;
        logic [31:0] tohost;
        @(posedge rst_n);
        forever begin
            @(posedge dut.clk_cluster[0]);
            cycles++;
            tohost = read_tohost();
            if (tohost != '0) begin
                $display("\n[tb_vex2] tohost = 0x%08h after %0d cluster cycles: %s", tohost, cycles,
                         tohost == 32'h1 ? "PASS" : "FAIL");
                $finish;
            end
            if (cycles == MAX_CYCLES) begin
                $display("\n[tb_vex2] TIMEOUT after %0d cluster cycles, pc 0x%08h", cycles, last_pc);
                $finish;
            end
        end
    end

endmodule
