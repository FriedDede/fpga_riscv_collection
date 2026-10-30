
#### IPs

# clocks in MHz, set by create_project.tcl (default 50)
#   core_clk_<n> cores (each core is its own clock domain, see hw/cluster/cd_wrappers)
#   cluster_clk  crossbar, bootrom, clint and hbm channel of the cluster
#   periph_clk   peripheral crossbar, uart, timer (and plic)
foreach f {core_freq_mhz cluster_freq_mhz periph_freq_mhz} {
    if {![info exists $f]} { set $f 50 }
}

# one per cluster (hw/cluster/cd_wrappers/cluster_clk_gen.sv): cluster clock + 6 core clocks,
# the outputs of the cores that are not instantiated are trimmed
set ipName xlnx_clk_gen_cluster
create_ip -name clk_wiz -vendor xilinx.com -library ip -module_name $ipName

set props [list CONFIG.PRIM_IN_FREQ {100.000} \
                CONFIG.NUM_OUT_CLKS {7} \
                CONFIG.CLKIN1_JITTER_PS {50.0} \
                CONFIG.CLK_OUT1_PORT {cluster_clk} \
                CONFIG.CLKOUT1_REQUESTED_OUT_FREQ $cluster_freq_mhz]
for {set n 0} {$n < 6} {incr n} {
    set o [expr {$n + 2}]
    lappend props CONFIG.CLKOUT${o}_USED {true} \
                  CONFIG.CLK_OUT${o}_PORT core_clk_$n \
                  CONFIG.CLKOUT${o}_REQUESTED_OUT_FREQ $core_freq_mhz
}
set_property -dict $props [get_ips $ipName]
generate_target {instantiation_template} [get_files $ipName.xci]

# shared by the peripherals
set ipName xlnx_clk_gen_periph
create_ip -name clk_wiz -vendor xilinx.com -library ip -module_name $ipName

set_property -dict [list CONFIG.PRIM_IN_FREQ {100.000} \
                        CONFIG.NUM_OUT_CLKS {1} \
                        CONFIG.CLKIN1_JITTER_PS {50.0} \
                        CONFIG.CLK_OUT1_PORT {periph_clk} \
                        CONFIG.CLKOUT1_REQUESTED_OUT_FREQ $periph_freq_mhz \
                       ] [get_ips $ipName]
generate_target {instantiation_template} [get_files $ipName.xci]
