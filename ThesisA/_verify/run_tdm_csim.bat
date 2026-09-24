@echo off
cd /d "D:\Thesis\ThesisA\hls_component"
call "D:\Xilinx\2026.1\Vitis\bin\vitis-run.bat" --mode hls --csim --config "D:\Thesis\ThesisA\hls_component\test_tdm.cfg" --work_dir hls_tdm
echo EXITCODE=%ERRORLEVEL%
