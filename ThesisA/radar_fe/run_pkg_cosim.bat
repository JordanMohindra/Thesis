@echo off
set XILINX_ROOT=D:\Xilinx\2026.1
cd /d D:\Thesis\ThesisA\radar_fe
echo START %TIME% > status_pkg.txt
call "%XILINX_ROOT%\Vitis\bin\vitis-run.bat" --mode hls --package --config ip_radar_fe.cfg --work_dir w_ip > pkg_fe.log 2>&1
echo pkg EXIT=%ERRORLEVEL% %TIME% >> status_pkg.txt
if exist w_ip\hls\impl\ip\component.xml (if exist ..\fpga_kcu116\ip_repo\radar_fe rmdir /s /q ..\fpga_kcu116\ip_repo\radar_fe & xcopy /e /i /q /y w_ip\hls\impl\ip ..\fpga_kcu116\ip_repo\radar_fe >nul & echo packaged >> status_pkg.txt)
call "%XILINX_ROOT%\Vitis\bin\vitis-run.bat" --mode hls --cosim --config cosim_fe.cfg --work_dir w_ip > cosim_fe.log 2>&1
echo cosim EXIT=%ERRORLEVEL% %TIME% >> status_pkg.txt
