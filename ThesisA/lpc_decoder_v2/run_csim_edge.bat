@echo off
cd /d "D:\Thesis\ThesisA\lpc_decoder_v2"
set SKIP_COLORADAR=1
call "D:\Xilinx\2026.1\Vitis\bin\vitis-run.bat" --mode hls --csim --config csim_equiv.cfg --work_dir w_csim > csim_edge.log 2>&1
echo EXIT=%ERRORLEVEL% >> csim_edge.log
