# Resume the lpc_full build after the MicroBlaze OOC synth ran out of memory.
# Re-uses every OOC run that already finished; re-runs only the incomplete ones, 2 jobs.
set root     D:/Thesis/ThesisA/fpga_kcu116
set out_dir  $root/out
set tag      lpc_full
set proj_dir $root/build/vivado_$tag
open_project $proj_dir/kcu116_$tag.xpr
foreach r [get_runs -filter {IS_SYNTHESIS}] {
    set p [get_property PROGRESS $r]
    puts "run $r progress=$p status=[get_property STATUS $r]"
    if {$p ne "100%" || $r eq "synth_1"} { reset_run $r }
}
launch_runs synth_1 -jobs 1
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { error "Synthesis failed - see $proj_dir" }
launch_runs impl_1 -to_step write_bitstream -jobs 2
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { error "Implementation failed - see $proj_dir" }
open_run impl_1
report_timing_summary -file $out_dir/kcu116_${tag}_timing.rpt
report_utilization    -file $out_dir/kcu116_${tag}_util.rpt
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "=== WNS = $wns ns ==="
set bit [lindex [glob -nocomplain $proj_dir/kcu116_$tag.runs/impl_1/*.bit] 0]
file copy -force $bit $out_dir/kcu116_${tag}.bit
write_hw_platform -fixed -include_bit -force $out_dir/kcu116_${tag}.xsa
set fp [open $out_dir/kcu116_${tag}.info w]
puts $fp "algo lpc\ntag $tag\ndecomp 1\nddr ddr4_sdram_075\nwns $wns"
close $fp
puts "=== DONE: $out_dir/kcu116_${tag}.bit and .xsa (WNS $wns ns) ==="
