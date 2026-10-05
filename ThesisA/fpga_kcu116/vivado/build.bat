@echo off
REM build.bat <drhe|lpc> [ddr4_sdram_075|ddr4_sdram_062] [jobs=3] [decomp=auto|0|1]  - builds bitstream + .xsa into ..\out
setlocal
if "%XILINX_ROOT%"=="" set XILINX_ROOT=D:\Xilinx\2026.1
set ALGO=%1
if "%ALGO%"=="" set ALGO=drhe
set DDR=%2
if "%DDR%"=="" set DDR=ddr4_sdram_075
set JOBS=%3
if "%JOBS%"=="" set JOBS=3
set DEC=%4
if "%DEC%"=="" set DEC=auto
cd /d "%~dp0"
call "%XILINX_ROOT%\Vivado\bin\vivado.bat" -mode batch -nojournal -log "build_%ALGO%.log" -source build_kcu116.tcl -tclargs %ALGO% %DDR% %JOBS% %DEC%
echo VIVADO EXIT=%ERRORLEVEL%
endlocal
