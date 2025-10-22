
#### IPs

set ipName xlnx_clk_gen_solo
create_ip -name clk_wiz -vendor xilinx.com -library ip -module_name $ipName

set_property -dict [list CONFIG.PRIM_IN_FREQ {100.000} \
                        CONFIG.NUM_OUT_CLKS {1} \
                        CONFIG.CLK_OUT1_PORT {core_clk} \
                        CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {50} \
                        CONFIG.CLKIN1_JITTER_PS {50.0} \
                       ] [get_ips $ipName]
