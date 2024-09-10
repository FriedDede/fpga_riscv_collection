set proj_dir $script_folder
#### IPs

set ipName xlnx_axi_clock_converter

create_ip -name axi_clock_converter -vendor xilinx.com -library ip -module_name $ipName
set_property -dict [list CONFIG.ADDR_WIDTH {64} CONFIG.DATA_WIDTH {64} CONFIG.ID_WIDTH {5}] [get_ips $ipName]
generate_target {instantiation_template} [get_files $proj_dir/ariane_u55.srcs/sources_1/ip/$ipName/$ipName.xci]

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

generate_target {instantiation_template} [get_files $proj_dir/ariane_u55.srcs/sources_1/ip/$ipName/$ipName.xci

set ipName xlnx_protocol_checker

create_ip -name axi_protocol_checker -vendor xilinx.com -library ip -version 2.0 -module_name $ipName

set_property -dict [list  CONFIG.ADDR_WIDTH {64} \
                          CONFIG.DATA_WIDTH {64} \
                          CONFIG.ID_WIDTH {5} \
                          CONFIG.AWUSER_WIDTH {1} \
                          CONFIG.ARUSER_WIDTH {1} \
                          CONFIG.RUSER_WIDTH {1} \
                          CONFIG.WUSER_WIDTH {1} \
                          CONFIG.BUSER_WIDTH {1} \
                          CONFIG.MAX_AW_WAITS {1024} \
                          CONFIG.MAX_AR_WAITS {1024} \
                          CONFIG.MAX_W_WAITS {1024} \
                          CONFIG.MAX_R_WAITS {1024} \
                          CONFIG.MAX_B_WAITS {1024} \
                          CONFIG.MAX_CONTINUOUS_WTRANSFERS_WAITS {1024} \
                          CONFIG.MAX_WLAST_TO_AWVALID_WAITS {1024} \
                          CONFIG.MAX_WRITE_TO_BVALID_WAITS {1024} \
                          CONFIG.MAX_CONTINUOUS_RTRANSFERS_WAITS {1024} \
                    ] [get_ips $ipName]

generate_target {instantiation_template} [get_files $proj_dir/ariane_u55.srcs/sources_1/ip/$ipName/$ipName.xci]