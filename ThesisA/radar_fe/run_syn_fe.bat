@echo off
set XILINX_ROOT=D:\Xilinx\2026.1
cd /d D:\Thesis\ThesisA\radar_fe
echo START %TIME% > status_syn.txt
call "%XILINX_ROOT%\Vitis\bin\v++.bat" -c --mode hls --config ip_radar_fe.cfg --work_dir w_ip > syn_fe.log 2>&1
echo syn EXIT=%ERRORLEVEL% %TIME% >> status_syn.txt
