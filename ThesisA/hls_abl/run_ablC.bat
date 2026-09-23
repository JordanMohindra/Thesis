@echo off
rem queue C: waits for queue A, then csim+syn+impl of kpk3 and kpk0
:w1
findstr /C:"ALLDONE_A" "D:\Thesis\ThesisA\hls_abl\impl.status" >nul 2>&1
if errorlevel 1 (ping -n 61 127.0.0.1 >nul & goto w1)
cd /d "D:\Thesis\ThesisA\hls_abl\kpk3"
echo START csim kpk3 %DATE% %TIME% >> "D:\Thesis\ThesisA\hls_abl\impl.status"
call "D:\Xilinx\2026.1\Vitis\bin\vitis-run.bat" --mode hls --csim --config abl.cfg --work_dir w > csim.log 2>&1
call "D:\Xilinx\2026.1\Vitis\bin\v++.bat" -c --mode hls --config abl.cfg --work_dir w > syn.log 2>&1
echo START impl kpk3 %DATE% %TIME% >> "D:\Thesis\ThesisA\hls_abl\impl.status"
call "D:\Xilinx\2026.1\Vitis\bin\vitis-run.bat" --mode hls --impl --config abl.cfg --work_dir w > impl.log 2>&1
echo END impl kpk3 EXIT=%ERRORLEVEL% %DATE% %TIME% >> "D:\Thesis\ThesisA\hls_abl\impl.status"
cd /d "D:\Thesis\ThesisA\hls_abl\kpk0"
echo START csim kpk0 %DATE% %TIME% >> "D:\Thesis\ThesisA\hls_abl\impl.status"
call "D:\Xilinx\2026.1\Vitis\bin\vitis-run.bat" --mode hls --csim --config abl.cfg --work_dir w > csim.log 2>&1
call "D:\Xilinx\2026.1\Vitis\bin\v++.bat" -c --mode hls --config abl.cfg --work_dir w > syn.log 2>&1
echo START impl kpk0 %DATE% %TIME% >> "D:\Thesis\ThesisA\hls_abl\impl.status"
call "D:\Xilinx\2026.1\Vitis\bin\vitis-run.bat" --mode hls --impl --config abl.cfg --work_dir w > impl.log 2>&1
echo END impl kpk0 EXIT=%ERRORLEVEL% %DATE% %TIME% >> "D:\Thesis\ThesisA\hls_abl\impl.status"
echo ALLDONE_C >> "D:\Thesis\ThesisA\hls_abl\impl.status"
