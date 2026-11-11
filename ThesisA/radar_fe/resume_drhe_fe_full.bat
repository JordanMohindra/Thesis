@echo off
set XILINX_ROOT=D:\Xilinx\2026.1
set ST=D:\Thesis\ThesisA\radar_fe\build_status.txt
echo [resume] DDR4 OOC synth ran out of memory; resuming with jobs=1 %DATE% %TIME% >> "%ST%"
cd /d D:\Thesis\ThesisA\radar_fe
call "%XILINX_ROOT%\Vivado\bin\vivado.bat" -mode batch -nojournal -log resume_drhe_fe_full.log -source resume_drhe_fe_full.tcl > resume_console.txt 2>&1
if exist D:\Thesis\ThesisA\fpga_kcu116\out\kcu116_drhe_fe_full.bit (echo vivado OK %DATE% %TIME% >> "%ST%") else (echo vivado FAILED %DATE% %TIME% >> "%ST%" & exit /b 1)
call "%XILINX_ROOT%\Vivado\bin\vivado.bat" -mode batch -nojournal -nolog -source hier_drhe_fe_full.tcl > hier.log 2>&1
echo hier done %TIME% >> "%ST%"
call D:\Thesis\ThesisA\fpga_kcu116\sw\build_sw.bat drhe_fe_full > D:\Thesis\ThesisA\radar_fe\sw_drhe_fe_full.log 2>&1
echo DONE %DATE% %TIME% >> "%ST%"
