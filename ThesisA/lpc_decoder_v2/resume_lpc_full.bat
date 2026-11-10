@echo off
set XILINX_ROOT=D:\Xilinx\2026.1
set ST=D:\Thesis\ThesisA\lpc_decoder_v2\rebuild_status.txt
echo [resume] MicroBlaze OOC synth ran out of memory at jobs=4; second resume, LPC compressor synth alone (jobs=1) %DATE% %TIME% >> "%ST%"
cd /d D:\Thesis\ThesisA\lpc_decoder_v2
call "%XILINX_ROOT%\Vivado\bin\vivado.bat" -mode batch -nojournal -log resume_lpc_full.log -source resume_lpc_full.tcl > resume_console.txt 2>&1
echo vivado done EXIT=%ERRORLEVEL% %DATE% %TIME% >> "%ST%"
call "%XILINX_ROOT%\Vivado\bin\vivado.bat" -mode batch -nojournal -nolog -source hier_lpc_full.tcl > hier.log 2>&1
echo hier done %DATE% %TIME% >> "%ST%"
call D:\Thesis\ThesisA\fpga_kcu116\sw\build_sw.bat lpc_full > D:\Thesis\ThesisA\lpc_decoder_v2\sw_lpc_full.log 2>&1
echo DONE %DATE% %TIME% >> "%ST%"
