@echo off
REM ==========================================================================
REM  export_ips.bat - C-simulate the TDM designs (writes golden outputs) and
REM  package the four cores as Vivado IP into ..\ip_repo
REM
REM  Run from a copy of the repo whose path has NO SPACES (Vitis refuses
REM  spaces), e.g.  D:\Thesis\ThesisA\fpga_kcu116\hls\export_ips.bat
REM  Optional: set XILINX_ROOT=D:\Xilinx\2026.1 before running.
REM ==========================================================================
setlocal EnableDelayedExpansion
if "%XILINX_ROOT%"=="" set XILINX_ROOT=D:\Xilinx\2026.1
set VPP="%XILINX_ROOT%\Vitis\bin\v++.bat"
set VRUN="%XILINX_ROOT%\Vitis\bin\vitis-run.bat"

set HERE=%~dp0
pushd "%HERE%.."
set ROOT=%CD%
popd
pushd "%ROOT%\..\hls_component" || (echo hls_component folder not found next to fpga_kcu116 & exit /b 1)
set SRC=%CD%
echo "%SRC%"| findstr /c:" " >nul && (echo ERROR: path "%SRC%" contains a space. Copy the repo to e.g. D:\Thesis first. & exit /b 1)
if not exist coloradar_multiframe.bin (echo ERROR: coloradar_multiframe.bin missing in %SRC% - export it from MATLAB first. & exit /b 1)

if not exist "%ROOT%\ip_repo" mkdir "%ROOT%\ip_repo"
if not exist "%ROOT%\golden"  mkdir "%ROOT%\golden"
set STATUS=%ROOT%\hls\export_status.txt
echo START %DATE% %TIME% > "%STATUS%"

REM ---- 1. C simulation of both TDM designs: lossless check + golden dumps ----
for %%A in (drhe lpc) do (
    if "%%A"=="drhe" (set CFG=test_tdm.cfg) else (set CFG=test_lpc_tdm.cfg)
    echo [csim] %%A ...
    call %VRUN% --mode hls --csim --config "%SRC%\!CFG!" --work_dir fk_csim_%%A > "%ROOT%\hls\csim_%%A.log" 2>&1
    echo csim_%%A EXIT=!ERRORLEVEL! >> "%STATUS%"
    if exist "fk_csim_%%A\hls\csim\build\golden_%%A_tdm_compressed.bin" copy /y "fk_csim_%%A\hls\csim\build\golden_%%A_tdm_compressed.bin" "%ROOT%\golden\" >nul
)

REM ---- 2. synthesise + package each core as IP --------------------------------
for %%T in (drhe_tdm_compress drhe_tdm_decompress lpc_tdm_compress lpc_tdm_decompress) do (
    echo [ip] %%T ...
    copy /y "%ROOT%\hls\ip_%%T.cfg" "%SRC%\ip_%%T.cfg" >nul
    call %VPP% -c --mode hls --config "%SRC%\ip_%%T.cfg" --work_dir fk_ip_%%T > "%ROOT%\hls\ip_%%T.log" 2>&1
    echo ip_%%T EXIT=!ERRORLEVEL! >> "%STATUS%"
    call %VRUN% --mode hls --package --config "%SRC%\ip_%%T.cfg" --work_dir fk_ip_%%T > "%ROOT%\hls\pkg_%%T.log" 2>&1
    echo pkg_%%T EXIT=!ERRORLEVEL! >> "%STATUS%"
    if exist "fk_ip_%%T\hls\impl\ip\component.xml" (
        if exist "%ROOT%\ip_repo\%%T" rmdir /s /q "%ROOT%\ip_repo\%%T"
        xcopy /e /i /q /y "fk_ip_%%T\hls\impl\ip" "%ROOT%\ip_repo\%%T" >nul
        echo    packaged to ip_repo\%%T
    ) else (
        echo    ERROR: no IP produced for %%T - see hls\ip_%%T.log
    )
)
echo DONE %DATE% %TIME% >> "%STATUS%"
popd
type "%STATUS%"
endlocal
