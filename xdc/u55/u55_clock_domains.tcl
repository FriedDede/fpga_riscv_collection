# Clock domain crossings between the clocks of the soc clock generators
# (tcl_scripts/gen_clock.tcl): per cluster xlnx_clk_gen_cluster (cluster and core clocks),
# xlnx_clk_gen_periph (peripheral clock). All these clocks are used as asynchronous to each
# other, even when they come from the same MMCM: every crossing goes through an axi_cdc
# (gray coded pointers) or a sync. The crossing paths are bounded to the period of the faster
# clock, without clock skew and hold checks.
# Unmanaged constraint file (tcl), applied in implementation only.

set cd_clocks [get_clocks -quiet -filter {NAME =~ *_xlnx_clk_gen_cluster* || NAME =~ *_xlnx_clk_gen_periph*}]
foreach src $cd_clocks {
    foreach dst $cd_clocks {
        if {$src ne $dst} {
            set period [expr {min([get_property PERIOD $src], [get_property PERIOD $dst])}]
            set_max_delay -datapath_only -from $src -to $dst $period
        }
    }
}

# asynchronous reset of the soc, released by a rstgen in each clock domain
set_false_path -through [get_nets -quiet -hierarchical -filter {NAME =~ *soc_rst_async_n}]

# hbm_interface block design: the reset of the HBM AXI ports (proc_sys_reset_1, 450 MHz axi_clk)
# is also sampled by the HBM IP in its APB clock domain (100 MHz apb_clk). The two clocks come from
# the same PLL (clk_wiz_0) and are timed as related, with the 1.1 ns of the closest edges. The reset
# is released once at startup: bound the crossing to one axi_clk period, without skew and hold
# checks (not a false path: one of the encrypted HBM endpoints is behind a LUT)
set hbm_axi_rst [get_cells -quiet -hierarchical -filter {NAME =~ */proc_sys_reset_1/U0/ACTIVE_LOW_PR_OUT_DFF[0].FDRE_PER_N}]
set hbm_apb_clk [get_clocks -quiet apb_clk_hbm_interface_clk_wiz_0_0]
set hbm_axi_clk [get_clocks -quiet axi_clk_hbm_interface_clk_wiz_0_0]
if {[llength $hbm_axi_rst] && [llength $hbm_apb_clk] && [llength $hbm_axi_clk]} {
    set_max_delay -datapath_only -from $hbm_axi_rst -to $hbm_apb_clk [get_property PERIOD $hbm_axi_clk]
}
