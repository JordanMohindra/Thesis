@echo off
cd /d "D:\Thesis\ThesisA\lpc_decoder_v2"
call "D:\Xilinx\2026.1\Vitis\bin\v++.bat" -c --mode hls --config syn_v2.cfg --work_dir w_syn > syn.log 2>&1
echo EXIT=%ERRORLEVEL% >> syn.log
