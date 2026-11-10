@echo off
set V="D:\Xilinx\2026.1\Vitis\bin\vitis-run.bat"
cd /d "D:\Thesis\ThesisA\lpc_decoder_v2"
call %V% --mode hls --csim --config csim_drhe_edge.cfg --work_dir w_drhe_edge > csim_drhe_edge.log 2>&1
echo EXIT=%ERRORLEVEL% >> csim_drhe_edge.log
cd /d "D:\Thesis\ThesisA\hls_component"
call %V% --mode hls --csim --config test_tdm.cfg --work_dir "D:\Thesis\ThesisA\lpc_decoder_v2\w_tb_drhe" > "D:\Thesis\ThesisA\lpc_decoder_v2\csim_tb_drhe.log" 2>&1
echo EXIT=%ERRORLEVEL% >> "D:\Thesis\ThesisA\lpc_decoder_v2\csim_tb_drhe.log"
call %V% --mode hls --csim --config test_lpc_tdm.cfg --work_dir "D:\Thesis\ThesisA\lpc_decoder_v2\w_tb_lpc" > "D:\Thesis\ThesisA\lpc_decoder_v2\csim_tb_lpc.log" 2>&1
echo EXIT=%ERRORLEVEL% >> "D:\Thesis\ThesisA\lpc_decoder_v2\csim_tb_lpc.log"
echo ALLDONE > "D:\Thesis\ThesisA\lpc_decoder_v2\csim_all.done"
