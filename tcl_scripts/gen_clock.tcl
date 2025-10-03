
#### IPs

set ipName xlnx_clk_gen_solo
create_ip -name clk_wiz -vendor xilinx.com -library ip -module_name $ipName

set_property -dict [list CONFIG.PRIM_IN_FREQ {100.000} \
                        CONFIG.NUM_OUT_CLKS {3} \
                        CONFIG.CLKOUT2_USED {true} \
                        CONFIG.CLKOUT3_USED {true} \
                        CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {50} \
                        CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {100} \
                        CONFIG.CLKOUT3_REQUESTED_OUT_FREQ {10} \
                        CONFIG.CLKIN1_JITTER_PS {50.0} \
                       ] [get_ips $ipName]

generate_target {instantiation_template} [get_files $proj_dir/ariane_u55.srcs/sources_1/ip/$ipName/$ipName.xci]