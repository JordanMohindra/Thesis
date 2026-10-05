@echo off
REM build_sw.bat <drhe|lpc>  - builds the MicroBlaze program into ..\out\radar_app_<algo>.elf
setlocal
if "%XILINX_ROOT%"=="" set XILINX_ROOT=D:\Xilinx\2026.1
set ALGO=%1
if "%ALGO%"=="" set ALGO=drhe
cd /d "%~dp0"
call "%XILINX_ROOT%\Vitis\bin\vitis.bat" -s build_sw.py %ALGO% > "build_sw_%ALGO%.log" 2>&1
echo VITIS EXIT=%ERRORLEVEL%  (log: sw\build_sw_%ALGO%.log)
endlocal
