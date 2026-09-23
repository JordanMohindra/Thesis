@echo off
rem queue D: after queue C, run k23
:w1
findstr /C:"ALLDONE_C" "D:\Thesis\ThesisA\hls_abl\impl.status" >nul 2>&1
if errorlevel 1 (ping -n 61 127.0.0.1 >nul & goto w1)
cd /d "D:\Thesis\ThesisA\hls_abl\k23"
if not exist "w\hls\syn\report\csynth.rpt" call "D:\Xilinx\2026.1\Vitis\bin\v++.bat" -c --mode hls --config abl.cfg --work_dir w > syn.log 2>&1
echo START impl k23 %DATE% %TIME% >> "D:\Thesis\ThesisA\hls_abl\impl.status"
call "D:\Xilinx\2026.1\Vitis\bin\vitis-run.bat" --mode hls --impl --config abl.cfg --work_dir w > impl.log 2>&1
echo END impl k23 EXIT=%ERRORLEVEL% %DATE% %TIME% >> "D:\Thesis\ThesisA\hls_abl\impl.status"
echo ALLDONE_D >> "D:\Thesis\ThesisA\hls_abl\impl.status"
