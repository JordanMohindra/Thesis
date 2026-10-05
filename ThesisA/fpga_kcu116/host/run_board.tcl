# =============================================================================
#  run_board.tcl  -  xsdb script: program the KCU116, load frames, run, dump
#
#  xsdb run_board.tcl <drhe|lpc> [nframes=50] [ndump]
#     ndump defaults to 5 when the bitstream has an on-chip decompressor and to
#     nframes when it does not (then every compressed frame is checked on the PC).
#
#  Needs (relative to this folder):
#     ../out/kcu116_<algo>.bit, ../out/radar_app_<algo>.elf   (built earlier)
#     ../out/frames_<nframes>.bin   (make_frames.py: frames without header)
#  Writes ../results/<algo>/results.bin and comp_<f>.bin for the first ndump
#  frames, then run compare_results.py.
#
#  The UART console (CP2105 UART1, 115200 8N1) shows the same results live.
# =============================================================================
set algo    [expr {[llength $argv] > 0 ? [lindex $argv 0] : "drhe"}]
set nframes [expr {[llength $argv] > 1 ? [lindex $argv 1] : 50}]

set here [file dirname [file normalize [info script]]]
set root [file normalize $here/..]
set bit    $root/out/kcu116_$algo.bit
set elf    $root/out/radar_app_$algo.elf
set frames $root/out/frames_$nframes.bin
set outdir $root/results/$algo
foreach f [list $bit $elf $frames] {
    if {![file exists $f]} { error "missing $f" }
}
# does this bitstream have the decompressor? (written by vivado/build_kcu116.tcl)
set decomp 1
set info $root/out/kcu116_$algo.info
if {[file exists $info]} {
    set fh [open $info]; set txt [read $fh]; close $fh
    regexp {decomp (\d)} $txt -> decomp
}
set ndump [expr {[llength $argv] > 2 ? [lindex $argv 2] : ($decomp ? 5 : $nframes)}]
if {$ndump > $nframes} { set ndump $nframes }
puts "algo $algo, $nframes frames, on-chip decompressor: $decomp, dumping $ndump compressed frames"
file mkdir $outdir

# addresses - must match sw/src/board_map.h
set IN_BASE       0x90000000
set COMP_OUT_BASE 0xA0000000
set COMP_SLOT     0x00100000
set RESULT_BASE   0xBF000000
set MBOX_BASE     0xBF100000

puts "== connect"
connect
puts [targets]

puts "== program FPGA with $bit"
targets -set -nocase -filter {name =~ "xcku5p*"}
fpga -file $bit
after 3000                                  ;# DDR4 calibration + reset release

puts "== MicroBlaze: reset + download $elf"
targets -set -nocase -filter {name =~ "*MicroBlaze*#0*"}
rst -processor
after 500
dow $elf

set t0 [clock milliseconds]
puts "== loading $nframes frames ([file size $frames] bytes) into DDR at $IN_BASE - this is slow over JTAG"
dow -data $frames $IN_BASE
set dt [expr {([clock milliseconds] - $t0) / 1000.0}]
puts [format "   loaded in %.1f s (%.0f KB/s)" $dt [expr {[file size $frames] / 1024.0 / max($dt, 0.001)}]]

mwr [expr {$MBOX_BASE + 0}] $nframes        ;# MBOX_NFRAMES
mwr [expr {$MBOX_BASE + 4}] 0               ;# MBOX_STATUS
mwr [expr {$MBOX_BASE + 8}] 0               ;# MBOX_DONE_CNT
mwr [expr {$MBOX_BASE + 20}] $decomp        ;# MBOX_FLAGS bit0 = decompressor present

puts "== run (watch the UART terminal)"
con
set t0 [clock milliseconds]
while {1} {
    after 2000
    stop
    set st   [mrd -value [expr {$MBOX_BASE + 4}]]
    set done [mrd -value [expr {$MBOX_BASE + 8}]]
    puts [format "   status 0x%08X  frames done %d / %d" $st $done $nframes]
    if {$st == 0xD0D0D0D0} { break }
    if {[clock milliseconds] - $t0 > 600000} { error "timed out waiting for the MicroBlaze" }
    con
}

puts "== dumping results"
mrd -bin -file $outdir/results.bin $RESULT_BASE [expr {$nframes * 8}]
for {set f 0} {$f < $ndump} {incr f} {
    set nbytes [mrd -value [expr {$RESULT_BASE + $f * 32 + 4}]]
    if {$nbytes == 0} { continue }
    set addr [expr {$COMP_OUT_BASE + $f * $COMP_SLOT}]
    mrd -bin -file $outdir/comp_$f.bin $addr [expr {($nbytes + 3) / 4}]
    puts "   frame $f: $nbytes compressed bytes -> comp_$f.bin"
}
set fp [open $outdir/run_info.txt w]
puts $fp "algo $algo\nnframes $nframes\nndump $ndump\ndecomp $decomp\nbit $bit\nelf $elf\ndate [clock format [clock seconds]]"
close $fp
puts "== done. Now run:  python compare_results.py $algo"
