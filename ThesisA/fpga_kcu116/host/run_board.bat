@echo off
REM run_board.bat <drhe|lpc> [nframes=50] [ndump=5]
setlocal
if "%XILINX_ROOT%"=="" set XILINX_ROOT=D:\Xilinx\2026.1
cd /d "%~dp0"
call "%XILINX_ROOT%\Vitis\bin\xsdb.bat" run_board.tcl %*
endlocal
