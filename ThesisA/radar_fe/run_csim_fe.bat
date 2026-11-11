@echo off
set XILINX_ROOT=D:\Xilinx\2026.1
cd /d D:\Thesis\ThesisA\radar_fe
echo START %DATE% %TIME% > status_csim.txt
call "%XILINX_ROOT%\Vitis\bin\vitis-run.bat" --mode hls --csim --config csim_fe.cfg --work_dir w_csim > csim_fe.log 2>&1
echo csim EXIT=%ERRORLEVEL% %DATE% %TIME% >> status_csim.txt
if exist w_csim\hls\csim\build\coloradar_multiframe_fe.bin copy /y w_csim\hls\csim\build\coloradar_multiframe_fe.bin . >nul
echo DONE >> status_csim.txt
