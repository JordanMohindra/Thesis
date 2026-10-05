# =============================================================================
#  build_kcu116.tcl  --  KCU116 test system for the DRHE / LPC compressors
#
#  Usage (from this folder, path must not contain spaces):
#     vivado -mode batch -source build_kcu116.tcl -tclargs <drhe|lpc> [ddr_iface] [jobs]
#
#     <drhe|lpc>   which compressor/decompressor pair to put on the board
#     ddr_iface    KCU116 board-file DDR4 interface. ddr4_sdram_075 (default)
#                  is the -075E memory part fitted to early boards and is safe
#                  on the later -062E part too (slower timings). Use
#                  ddr4_sdram_062 only if you know your board has the -062E.
#
#  Produces  ../out/kcu116_<algo>.bit   (bitstream)
#            ../out/kcu116_<algo>.xsa   (hardware handoff for Vitis)
#            ../out/kcu116_<algo>_timing.rpt, _util.rpt
#
#  System (all at 100 MHz except the DDR4 controller's own 333 MHz domain):
#
#   MicroBlaze (128 KB LMB, debug via MDM/JTAG)
#        |  M_AXI_DP
#   AXI SmartConnect ---- DDR4 1 GB @ 0x8000_0000 (board files)
#        |       \------- UART Lite (115200, CP2105 UART1), AXI Timer, LED GPIO
#        |       \------- dma_c / dma_d control, comp / decomp control
#   dma_c: DDR --MM2S 128b--> <algo>_tdm_compress   --256b--> S2MM --> DDR
#   dma_d: DDR --MM2S 256b--> <algo>_tdm_decompress --128b--> S2MM --> DDR
#
#  The address map is fixed here and mirrored in ../sw/src/board_map.h.
# =============================================================================

set algo    [expr {[llength $argv] > 0 ? [lindex $argv 0] : "drhe"}]
set ddr_if  [expr {[llength $argv] > 1 ? [lindex $argv 1] : "ddr4_sdram_075"}]
# parallel synthesis jobs: each needs ~3.5 GB of RAM, so keep this low on a 16 GB PC
set jobs    [expr {[llength $argv] > 2 ? [lindex $argv 2] : 3}]
# include the decompressor on chip? "auto" = LPC yes, DRHE no. The DRHE
# decompressor synthesises to ~182k LUTs on its own, so compressor +
# decompressor (235k LUTs) do not fit the XCKU5P (217k). For DRHE the board
# therefore compresses only, and losslessness is proven on the host by a
# byte-for-byte match with the C-simulation bitstream (host/compare_results.py).
set decomp  [expr {[llength $argv] > 3 ? [lindex $argv 3] : "auto"}]
if {$decomp eq "auto"} { set decomp [expr {$algo eq "lpc" ? 1 : 0}] }
if {$algo ni {drhe lpc}} { error "first argument must be drhe or lpc, got '$algo'" }

set here     [file dirname [file normalize [info script]]]
set root     [file normalize $here/..]
set ip_repo  [file normalize $root/ip_repo]
set out_dir  [file normalize $root/out]
set proj_dir [file normalize $root/build/vivado_$algo]
file mkdir $out_dir
if {[string first " " $proj_dir] >= 0} { error "Project path contains a space: $proj_dir. Copy fpga_kcu116 to a path without spaces (e.g. D:/Thesis/ThesisA/fpga_kcu116)." }

puts "=== KCU116 build: algo=$algo ddr=$ddr_if jobs=$jobs decompressor=$decomp ==="

# ---------------------------------------------------------------- project ----
create_project kcu116_$algo $proj_dir -part xcku5p-ffvb676-2-e -force
set bp [lindex [lsort [get_board_parts -quiet xilinx.com:kcu116:*]] end]
if {$bp eq ""} { error "KCU116 board files not found. In Vivado: Tools > Xilinx Board Store > install KCU116." }
set_property board_part $bp [current_project]
puts "Board part: $bp"

set_property ip_repo_paths [list $ip_repo] [current_project]
update_ip_catalog -rebuild

proc find_ip {name} {
    set d [lindex [lsort [get_ipdefs -quiet -filter "NAME == $name"]] end]
    if {$d eq ""} { error "IP '$name' not found in the IP repository ($::ip_repo). Run ../hls/export_ips.bat first." }
    return $d
}
set comp_vlnv   [find_ip ${algo}_tdm_compress]
if {$decomp} { set decomp_vlnv [find_ip ${algo}_tdm_decompress] }

# ------------------------------------------------------------ block design ---
create_bd_design system

# ---- DDR4 (board interface) -------------------------------------------------
set ddr [create_bd_cell -type ip -vlnv xilinx.com:ip:ddr4 ddr4_0]
set_property -dict [list \
    CONFIG.C0_DDR4_BOARD_INTERFACE $ddr_if \
    CONFIG.C0_CLOCK_BOARD_INTERFACE default_sysclk1_300 \
    CONFIG.RESET_BOARD_INTERFACE reset \
    CONFIG.ADDN_UI_CLKOUT1_FREQ_HZ 100] $ddr
# Run the DDR4 at 2400 MT/s rather than the 2666 maximum: the bandwidth needed
# here is tiny, and at 2666 the XIPHY showed min-skew pulse-width violations.
if {[catch {set_property CONFIG.C0.DDR4_TimePeriod 833 $ddr} err]} { puts "note: DDR4 speed left at default ($err)" }
apply_bd_automation -rule xilinx.com:bd_rule:board -config [list Board_Interface $ddr_if]        [get_bd_intf_pins ddr4_0/C0_DDR4]
apply_bd_automation -rule xilinx.com:bd_rule:board -config [list Board_Interface default_sysclk1_300] [get_bd_intf_pins ddr4_0/C0_SYS_CLK]
apply_bd_automation -rule xilinx.com:bd_rule:board -config [list Board_Interface reset]           [get_bd_pins ddr4_0/sys_rst]

set clk    [get_bd_pins ddr4_0/addn_ui_clkout1]   ;# 100 MHz system clock
set ui_clk [get_bd_pins ddr4_0/c0_ddr4_ui_clk]    ;# DDR4 controller clock

# ---- resets ------------------------------------------------------------------
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset rst_100
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset rst_ddr
# ext_reset_in polarity is derived automatically from ddr4_0/c0_ddr4_ui_clk_sync_rst (active high)
connect_bd_net $clk    [get_bd_pins rst_100/slowest_sync_clk]
connect_bd_net $ui_clk [get_bd_pins rst_ddr/slowest_sync_clk]
connect_bd_net [get_bd_pins ddr4_0/c0_ddr4_ui_clk_sync_rst] [get_bd_pins rst_100/ext_reset_in] [get_bd_pins rst_ddr/ext_reset_in]
connect_bd_net [get_bd_pins ddr4_0/c0_init_calib_complete]   [get_bd_pins rst_100/dcm_locked]   [get_bd_pins rst_ddr/dcm_locked]
connect_bd_net [get_bd_pins rst_ddr/peripheral_aresetn] [get_bd_pins ddr4_0/c0_ddr4_aresetn]

# ---- MicroBlaze + local memory ----------------------------------------------
set mb_vlnv [lindex [lsort [get_ipdefs -quiet xilinx.com:ip:microblaze:*]] end]
set mb_is_riscv 0
if {$mb_vlnv eq ""} {
    set mb_vlnv [lindex [lsort [get_ipdefs -quiet xilinx.com:ip:microblaze_riscv:*]] end]
    set mb_is_riscv 1
}
if {$mb_vlnv eq ""} { error "Neither MicroBlaze nor MicroBlaze V found in the IP catalog." }
puts "Processor: $mb_vlnv"
set mb [create_bd_cell -type ip -vlnv $mb_vlnv microblaze_0]
foreach {k v} {C_D_AXI 1 C_D_LMB 1 C_I_LMB 1 C_DEBUG_ENABLED 1 C_USE_BARREL 1 C_USE_HW_MUL 1 C_USE_DIV 1} {
    if {[catch {set_property CONFIG.$k $v $mb} err]} { puts "note: $k not set ($err)" }
}

create_bd_cell -type ip -vlnv xilinx.com:ip:mdm mdm_0
connect_bd_intf_net [get_bd_intf_pins mdm_0/MBDEBUG_0] [get_bd_intf_pins microblaze_0/DEBUG]

create_bd_cell -type ip -vlnv xilinx.com:ip:lmb_v10 dlmb
create_bd_cell -type ip -vlnv xilinx.com:ip:lmb_v10 ilmb
create_bd_cell -type ip -vlnv xilinx.com:ip:lmb_bram_if_cntlr dlmb_cntlr
create_bd_cell -type ip -vlnv xilinx.com:ip:lmb_bram_if_cntlr ilmb_cntlr
create_bd_cell -type ip -vlnv xilinx.com:ip:blk_mem_gen lmb_bram
set_property -dict [list CONFIG.Memory_Type True_Dual_Port_RAM CONFIG.use_bram_block BRAM_Controller] [get_bd_cells lmb_bram]
connect_bd_intf_net [get_bd_intf_pins microblaze_0/DLMB] [get_bd_intf_pins dlmb/LMB_M]
connect_bd_intf_net [get_bd_intf_pins microblaze_0/ILMB] [get_bd_intf_pins ilmb/LMB_M]
connect_bd_intf_net [get_bd_intf_pins dlmb/LMB_Sl_0]    [get_bd_intf_pins dlmb_cntlr/SLMB]
connect_bd_intf_net [get_bd_intf_pins ilmb/LMB_Sl_0]    [get_bd_intf_pins ilmb_cntlr/SLMB]
connect_bd_intf_net [get_bd_intf_pins dlmb_cntlr/BRAM_PORT] [get_bd_intf_pins lmb_bram/BRAM_PORTA]
connect_bd_intf_net [get_bd_intf_pins ilmb_cntlr/BRAM_PORT] [get_bd_intf_pins lmb_bram/BRAM_PORTB]

connect_bd_net $clk [get_bd_pins microblaze_0/Clk] [get_bd_pins dlmb/LMB_Clk] [get_bd_pins ilmb/LMB_Clk] \
                    [get_bd_pins dlmb_cntlr/LMB_Clk] [get_bd_pins ilmb_cntlr/LMB_Clk]
connect_bd_net [get_bd_pins rst_100/mb_reset]          [get_bd_pins microblaze_0/Reset]
connect_bd_net [get_bd_pins rst_100/bus_struct_reset]  [get_bd_pins dlmb/SYS_Rst] [get_bd_pins ilmb/SYS_Rst] \
                                                       [get_bd_pins dlmb_cntlr/LMB_Rst] [get_bd_pins ilmb_cntlr/LMB_Rst]
connect_bd_net [get_bd_pins mdm_0/Debug_SYS_Rst]       [get_bd_pins rst_100/mb_debug_sys_rst]

# ---- peripherals ------------------------------------------------------------
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_uartlite uart_0
set_property -dict [list CONFIG.UARTLITE_BOARD_INTERFACE rs232_uart CONFIG.C_BAUDRATE 115200] [get_bd_cells uart_0]
apply_bd_automation -rule xilinx.com:bd_rule:board -config [list Board_Interface rs232_uart] [get_bd_intf_pins uart_0/UART]

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_timer timer_0

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio gpio_led
set_property -dict [list CONFIG.GPIO_BOARD_INTERFACE led_8bits] [get_bd_cells gpio_led]
apply_bd_automation -rule xilinx.com:bd_rule:board -config [list Board_Interface led_8bits] [get_bd_intf_pins gpio_led/GPIO]

# ---- DMAs + compressor / decompressor -----------------------------------------
proc make_dma {name mm2s_w s2mm_w} {
    set d [create_bd_cell -type ip -vlnv xilinx.com:ip:axi_dma $name]
    set_property -dict [list \
        CONFIG.c_include_sg 0 \
        CONFIG.c_sg_length_width 26 \
        CONFIG.c_addr_width 32 \
        CONFIG.c_m_axi_mm2s_data_width $mm2s_w \
        CONFIG.c_m_axis_mm2s_tdata_width $mm2s_w \
        CONFIG.c_m_axi_s2mm_data_width $s2mm_w \
        CONFIG.c_s_axis_s2mm_tdata_width $s2mm_w \
        CONFIG.c_mm2s_burst_size 64 \
        CONFIG.c_s2mm_burst_size 64] $d
    return $d
}
make_dma dma_c 128 256
create_bd_cell -type ip -vlnv $comp_vlnv   comp
connect_bd_intf_net [get_bd_intf_pins dma_c/M_AXIS_MM2S] [get_bd_intf_pins comp/in_stream]
connect_bd_intf_net [get_bd_intf_pins comp/out_stream]   [get_bd_intf_pins dma_c/S_AXIS_S2MM]
if {$decomp} {
    make_dma dma_d 256 128
    create_bd_cell -type ip -vlnv $decomp_vlnv decomp
    connect_bd_intf_net [get_bd_intf_pins dma_d/M_AXIS_MM2S] [get_bd_intf_pins decomp/in_stream]
    connect_bd_intf_net [get_bd_intf_pins decomp/out_stream] [get_bd_intf_pins dma_d/S_AXIS_S2MM]
}

# ---- interconnect -----------------------------------------------------------
set sc [create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect sc_0]
set_property -dict [list CONFIG.NUM_SI [expr {$decomp ? 5 : 3}] CONFIG.NUM_MI [expr {$decomp ? 8 : 6}] CONFIG.NUM_CLKS 2] $sc
connect_bd_intf_net [get_bd_intf_pins microblaze_0/M_AXI_DP] [get_bd_intf_pins sc_0/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins dma_c/M_AXI_MM2S]      [get_bd_intf_pins sc_0/S01_AXI]
connect_bd_intf_net [get_bd_intf_pins dma_c/M_AXI_S2MM]      [get_bd_intf_pins sc_0/S02_AXI]
if {$decomp} {
    connect_bd_intf_net [get_bd_intf_pins dma_d/M_AXI_MM2S]  [get_bd_intf_pins sc_0/S03_AXI]
    connect_bd_intf_net [get_bd_intf_pins dma_d/M_AXI_S2MM]  [get_bd_intf_pins sc_0/S04_AXI]
}
connect_bd_intf_net [get_bd_intf_pins sc_0/M00_AXI] [get_bd_intf_pins ddr4_0/C0_DDR4_S_AXI]
connect_bd_intf_net [get_bd_intf_pins sc_0/M01_AXI] [get_bd_intf_pins uart_0/S_AXI]
connect_bd_intf_net [get_bd_intf_pins sc_0/M02_AXI] [get_bd_intf_pins timer_0/S_AXI]
connect_bd_intf_net [get_bd_intf_pins sc_0/M03_AXI] [get_bd_intf_pins gpio_led/S_AXI]
connect_bd_intf_net [get_bd_intf_pins sc_0/M04_AXI] [get_bd_intf_pins dma_c/S_AXI_LITE]
connect_bd_intf_net [get_bd_intf_pins sc_0/M05_AXI] [get_bd_intf_pins comp/s_axi_control]
if {$decomp} {
    connect_bd_intf_net [get_bd_intf_pins sc_0/M06_AXI] [get_bd_intf_pins dma_d/S_AXI_LITE]
    connect_bd_intf_net [get_bd_intf_pins sc_0/M07_AXI] [get_bd_intf_pins decomp/s_axi_control]
}

connect_bd_net $clk    [get_bd_pins sc_0/aclk]
connect_bd_net $ui_clk [get_bd_pins sc_0/aclk1]
connect_bd_net [get_bd_pins rst_100/interconnect_aresetn] [get_bd_pins sc_0/aresetn]

# 100 MHz clock + reset to every AXI peripheral
set clk_pins {uart_0/s_axi_aclk timer_0/s_axi_aclk gpio_led/s_axi_aclk \
              dma_c/s_axi_lite_aclk dma_c/m_axi_mm2s_aclk dma_c/m_axi_s2mm_aclk comp/ap_clk}
set rst_pins {uart_0/s_axi_aresetn timer_0/s_axi_aresetn gpio_led/s_axi_aresetn dma_c/axi_resetn comp/ap_rst_n}
if {$decomp} {
    lappend clk_pins dma_d/s_axi_lite_aclk dma_d/m_axi_mm2s_aclk dma_d/m_axi_s2mm_aclk decomp/ap_clk
    lappend rst_pins dma_d/axi_resetn decomp/ap_rst_n
}
foreach p $clk_pins { connect_bd_net $clk [get_bd_pins $p] }
foreach p $rst_pins { connect_bd_net [get_bd_pins rst_100/peripheral_aresetn] [get_bd_pins $p] }

# ---- address map (mirrored in sw/src/board_map.h) ---------------------------
set dspace [get_bd_addr_spaces microblaze_0/Data]
set ispace [get_bd_addr_spaces microblaze_0/Instruction]
assign_bd_address -offset 0x00000000 -range 128K -target_address_space $dspace [get_bd_addr_segs dlmb_cntlr/SLMB/Mem] -force
assign_bd_address -offset 0x00000000 -range 128K -target_address_space $ispace [get_bd_addr_segs ilmb_cntlr/SLMB/Mem] -force

set ddr_seg [get_bd_addr_segs ddr4_0/C0_DDR4_MEMORY_MAP/C0_DDR4_ADDRESS_BLOCK]
set dma_spaces {dma_c/Data_MM2S dma_c/Data_S2MM}
if {$decomp} { lappend dma_spaces dma_d/Data_MM2S dma_d/Data_S2MM }
foreach sp [concat [list $dspace] [lmap x $dma_spaces {get_bd_addr_spaces $x}]] {
    assign_bd_address -offset 0x80000000 -range 1G -target_address_space $sp $ddr_seg -force
}
proc seg_of {intf} { return [get_bd_addr_segs -of_objects [get_bd_intf_pins $intf]] }
assign_bd_address -offset 0x40000000 -range 64K -target_address_space $dspace [seg_of gpio_led/S_AXI]       -force
assign_bd_address -offset 0x40600000 -range 64K -target_address_space $dspace [seg_of uart_0/S_AXI]         -force
assign_bd_address -offset 0x41C00000 -range 64K -target_address_space $dspace [seg_of timer_0/S_AXI]        -force
assign_bd_address -offset 0x41E00000 -range 64K -target_address_space $dspace [seg_of dma_c/S_AXI_LITE]     -force
assign_bd_address -offset 0x44A00000 -range 64K -target_address_space $dspace [seg_of comp/s_axi_control]   -force
if {$decomp} {
    assign_bd_address -offset 0x41E10000 -range 64K -target_address_space $dspace [seg_of dma_d/S_AXI_LITE]     -force
    assign_bd_address -offset 0x44A10000 -range 64K -target_address_space $dspace [seg_of decomp/s_axi_control] -force
}

# the DMAs only ever address DDR: exclude every control-register segment from them
set ctrl_intfs {gpio_led/S_AXI uart_0/S_AXI timer_0/S_AXI dma_c/S_AXI_LITE comp/s_axi_control}
if {$decomp} { lappend ctrl_intfs dma_d/S_AXI_LITE decomp/s_axi_control }
foreach sp $dma_spaces {
    foreach intf $ctrl_intfs {
        catch { exclude_bd_addr_seg -target_address_space [get_bd_addr_spaces $sp] [seg_of $intf] }
    }
}

regenerate_bd_layout
validate_bd_design
save_bd_design

# ------------------------------------------------------------- implement ----
# c0_init_calib_complete (DDR4 controller clock) feeds the asynchronous
# dcm_locked input of the 100 MHz reset block; it is not a synchronous path.
set xdc $proj_dir/system_cdc.xdc
set fh [open $xdc w]
puts $fh {set_false_path -from [get_cells -hierarchical -filter {NAME =~ *u_ddr_cal_top/calDone_gated_reg}] -to [get_cells -hierarchical -filter {NAME =~ *rst_100/U0/EXT_LPF/*}]}
puts $fh {set_false_path -from [get_cells -hierarchical -filter {NAME =~ *u_ddr_cal_top/calDone_gated_reg}] -to [get_cells -hierarchical -filter {NAME =~ *rst_ddr/U0/EXT_LPF/*}]}
close $fh
add_files -fileset constrs_1 -norecurse $xdc

set bd_file [get_files system.bd]
generate_target all $bd_file
set wrapper [make_wrapper -files $bd_file -top]
add_files -norecurse $wrapper
set_property top system_wrapper [current_fileset]
update_compile_order -fileset sources_1

launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { error "Synthesis failed - see $proj_dir" }
launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { error "Implementation failed - see $proj_dir" }

open_run impl_1
report_timing_summary -file $out_dir/kcu116_${algo}_timing.rpt
report_utilization    -file $out_dir/kcu116_${algo}_util.rpt
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
puts "=== WNS = $wns ns ==="
if {$wns < 0} { puts "WARNING: timing not met (WNS $wns ns) - the board may not behave correctly." }

set bit [lindex [glob -nocomplain $proj_dir/kcu116_$algo.runs/impl_1/*.bit] 0]
file copy -force $bit $out_dir/kcu116_${algo}.bit
write_hw_platform -fixed -include_bit -force $out_dir/kcu116_${algo}.xsa
set fp [open $out_dir/kcu116_${algo}.info w]
puts $fp "algo $algo\ndecomp $decomp\nddr $ddr_if\nwns $wns"
close $fp
puts "=== DONE: $out_dir/kcu116_${algo}.bit and .xsa (WNS $wns ns) ==="
