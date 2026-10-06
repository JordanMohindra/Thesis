@echo off
REM ==========================================================================
REM  pc_decompress.bat <drhe|lpc>  -  decompress the board's output on the PC
REM
REM  Uses results\<algo>\comp_<f>.bin from run_board.bat, runs the verified
REM  decompressor C++ through Vitis C simulation, writes recon_<f>.bin and
REM  pc_decompress.txt next to them, and compares every frame with the
REM  original in out\frames_<n>.bin. Then run compare_results.py.
REM  Path must not contain spaces (Vitis restriction).
REM ==========================================================================
setlocal
if "%XILINX_ROOT%"=="" set XILINX_ROOT=D:\Xilinx\2026.1
set ALGO=%1
if "%ALGO%"=="" set ALGO=drhe
pushd "%~dp0.."
set ROOT=%CD%
popd
pushd "%ROOT%\..\hls_component"
set SRC=%CD%
popd
set RDIR=%ROOT%\results\%ALGO%
if not exist "%RDIR%\run_info.txt" (echo ERROR: no board results in %RDIR% - run run_board.bat %ALGO% first & exit /b 1)
for /f "tokens=1,2" %%a in (%RDIR%\run_info.txt) do if "%%a"=="nframes" set NFR=%%b
set FRAMES=%ROOT%\out\frames_%NFR%.bin

set WORK=%ROOT%\build\pc_decompress_%ALGO%
if not exist "%WORK%" mkdir "%WORK%"
set PCD_JOB=%WORK%\job.txt
(echo %ALGO%& echo %FRAMES%& echo %NFR%& echo %RDIR%) > "%PCD_JOB%"

set DEF=ALGO_DRHE
if /i "%ALGO%"=="lpc" set DEF=ALGO_LPC
set CFG=%WORK%\pc_decompress.cfg
(
echo part=xcku5p-ffvb676-2-e
echo [hls]
echo clock=100MHz
echo syn.file=%SRC%\%ALGO%_tdm_decompress.cpp
echo syn.top=%ALGO%_tdm_decompress
echo tb.file=%ROOT%\host\pc_decompress\pc_decompress_tb.cpp
echo tb.cflags=-I%SRC% -D%DEF%
echo csim.O=true
) > "%CFG%"

echo Decompressing %NFR% %ALGO% frames on the PC ...
call "%XILINX_ROOT%\Vitis\bin\vitis-run.bat" --mode hls --csim --config "%CFG%" --work_dir "%WORK%\hls_work" > "%WORK%\csim.log" 2>&1
findstr /c:"frame " /c:"[RESULT]" /c:"[ERROR]" "%WORK%\csim.log"
echo (full log: %WORK%\csim.log)
endlocal
