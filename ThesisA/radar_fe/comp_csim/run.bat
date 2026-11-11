@echo off
set XILINX_ROOT=D:\Xilinx\2026.1
cd /d D:\Thesis\ThesisA\radar_fe\comp_csim
echo START %TIME% > status.txt
call "%XILINX_ROOT%\Vitis\bin\vitis-run.bat" --mode hls --csim --config csim_drhe.cfg --work_dir w_drhe > csim_drhe.log 2>&1
echo drhe EXIT=%ERRORLEVEL% %TIME% >> status.txt
call "%XILINX_ROOT%\Vitis\bin\vitis-run.bat" --mode hls --csim --config csim_lpc.cfg --work_dir w_lpc > csim_lpc.log 2>&1
echo lpc EXIT=%ERRORLEVEL% %TIME% >> status.txt
copy /y w_drhe\hls\csim\build\golden_drhe_tdm_compressed.bin golden_drhe_fe_compressed.bin >nul
copy /y w_lpc\hls\csim\build\golden_lpc_tdm_compressed.bin golden_lpc_fe_compressed.bin >nul
echo DONE >> status.txt
