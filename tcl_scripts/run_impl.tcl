# Copyright 2024 Politecnico di Milano.
# Solderpad Hardware License, Version 0.51, see LICENSE for details.
#
# Description: synthesis, implementation and bitstream of a project made by create_project.tcl
# Usage: vivado -mode batch -source tcl_scripts/run_impl.tcl -tclargs <project.xpr> <jobs>
# Author: Andrea Motta

lassign $argv xpr jobs
open_project $xpr
set proj_dir [get_property directory [current_project]]
set proj_name [get_property name [current_project]]

# rerun from scratch so the bitstream always matches the current sources
reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1

if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    error "synthesis failed: [get_property STATUS [get_runs synth_1]]"
}
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "implementation failed: [get_property STATUS [get_runs impl_1]]"
}

open_run impl_1
report_timing_summary -max_paths 20 -file $proj_dir/timing_summary.rpt
report_utilization -hierarchical -hierarchical_depth 3 -file $proj_dir/utilization.rpt

set bit [glob -nocomplain [get_property DIRECTORY [get_runs impl_1]]/*.bit]
file copy -force $bit $proj_dir/$proj_name.bit

set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
puts "INFO: bitstream $proj_dir/$proj_name.bit"
puts "INFO: WNS $wns ns, WHS $whs ns (reports in $proj_dir)"
if {$wns < 0 || $whs < 0} {
    puts "CRITICAL WARNING: timing not met"
}
close_project
