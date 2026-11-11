@echo off
set XILINX_ROOT=D:\Xilinx\2026.1
set ST=D:\Thesis\ThesisA\radar_fe\build_status.txt
echo [vivado] drhe_fe_full %DATE% %TIME% > "%ST%"
call D:\Thesis\ThesisA\fpga_kcu116\vivado\build.bat drhe ddr4_sdram_075 2 1 1 > D:\Thesis\ThesisA\radar_fe\vivado_drhe_fe_full.log 2>&1
if exist D:\Thesis\ThesisA\fpga_kcu116\out\kcu116_drhe_fe_full.bit (echo vivado OK %DATE% %TIME% >> "%ST%") else (echo vivado FAILED %DATE% %TIME% >> "%ST%" & exit /b 1)
cd /d D:\Thesis\ThesisA\radar_fe
call "%XILINX_ROOT%\Vivado\bin\vivado.bat" -mode batch -nojournal -nolog -source hier_drhe_fe_full.tcl > hier.log 2>&1
echo hier done %TIME% >> "%ST%"
call D:\Thesis\ThesisA\fpga_kcu116\sw\build_sw.bat drhe_fe_full > D:\Thesis\ThesisA\radar_fe\sw_drhe_fe_full.log 2>&1
echo DONE %DATE% %TIME% >> "%ST%"
