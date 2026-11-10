@echo off
cd /d "D:\Thesis\ThesisA\lpc_decoder_v2"
call "D:\Xilinx\2026.1\Vitis\bin\vitis-run.bat" --mode hls --csim --config csim_equiv.cfg --work_dir w_csim > csim.log 2>&1
echo EXIT=%ERRORLEVEL% >> csim.log
