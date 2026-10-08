foreach a {drhe lpc} {
 open_project D:/Thesis/ThesisA/fpga_kcu116/build/vivado_$a/kcu116_$a.xpr
 open_bd_design [get_files system.bd]
 write_bd_layout -force -format pdf -orientation landscape D:/Thesis/ThesisA/fpga_kcu116/out/block_design_$a.pdf
 write_bd_layout -force -format svg D:/Thesis/ThesisA/fpga_kcu116/out/block_design_$a.svg
 close_project
}
exit
