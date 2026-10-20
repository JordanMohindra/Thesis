# per-core utilisation of the builds with the on-chip decompressor
foreach a {drhe_full lpc_full} {
 open_checkpoint D:/Thesis/ThesisA/fpga_kcu116/build/vivado_$a/kcu116_$a.runs/impl_1/system_wrapper_routed.dcp
 report_utilization -hierarchical -hierarchical_depth 2 -file D:/Thesis/ThesisA/fpga_kcu116/out/kcu116_${a}_util_hier.rpt
 close_design
}
