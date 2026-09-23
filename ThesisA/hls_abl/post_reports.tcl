# post_reports.tcl  <routed.dcp> <out_dir>
# Opens a routed checkpoint and writes every report the thesis cites.
set dcp [lindex $argv 0]
set out [lindex $argv 1]
file mkdir $out
open_checkpoint $dcp
report_utilization                                   -file $out/util.rpt
report_utilization -hierarchical -hierarchical_depth 8 -file $out/util_hier.rpt
report_timing_summary -max_paths 10 -report_unconstrained -file $out/timing_summary.rpt
report_timing -max_paths 20 -nworst 1 -sort_by slack -file $out/timing_paths.rpt
report_design_analysis -logic_level_distribution -file $out/logic_levels.rpt
report_power -file $out/power.rpt
report_power -hier all -hierarchical_depth 4 -file $out/power_hier.rpt
# achieved clock: 10 ns constraint minus WNS
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set f [open $out/fmax.txt w]
puts $f "WNS_ns $wns"
puts $f "achieved_period_ns [expr {10.0 - $wns}]"
puts $f "achieved_fmax_MHz [expr {1000.0 / (10.0 - $wns)}]"
close $f
close_design
