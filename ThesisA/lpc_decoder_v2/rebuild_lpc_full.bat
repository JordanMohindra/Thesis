@echo off
set XILINX_ROOT=D:\Xilinx\2026.1
set ST=D:\Thesis\ThesisA\lpc_decoder_v2\rebuild_status.txt
echo START %DATE% %TIME% > "%ST%"
:waitcsim
if not exist "D:\Thesis\ThesisA\lpc_decoder_v2\csim_all.done" (timeout /t 20 /nobreak >nul & goto waitcsim)
copy /y "C:\Users\Jordan Mohindra\OneDrive\Documents\Fifth_Year\_lpc_xfer\v3_lpc_tdm_decompress.cpp" "D:\Thesis\ThesisA\hls_component\lpc_tdm_decompress.cpp" >nul
copy /y "C:\Users\Jordan Mohindra\OneDrive\Documents\Fifth_Year\_lpc_xfer\v3_lpc_tdm_decompress.cpp" "D:\Thesis\ThesisA\lpc_decoder_v2\lpc_tdm_decompress.cpp" >nul
cd /d D:\Thesis\ThesisA\lpc_decoder_v2
call "%XILINX_ROOT%\Vitis\bin\v++.bat" -c --mode hls --config syn_v2.cfg --work_dir w_syn3 > syn3.log 2>&1
echo syn3 EXIT=%ERRORLEVEL% >> "%ST%"
cd /d D:\Thesis\ThesisA\hls_component
for %%T in (lpc_tdm_compress lpc_tdm_decompress) do (
  copy /y "D:\Thesis\ThesisA\fpga_kcu116\hls\ip_%%T.cfg" "D:\Thesis\ThesisA\hls_component\ip_%%T.cfg" >nul
  call "%XILINX_ROOT%\Vitis\bin\v++.bat" -c --mode hls --config "D:\Thesis\ThesisA\hls_component\ip_%%T.cfg" --work_dir fk_ip_%%T > "D:\Thesis\ThesisA\lpc_decoder_v2\ip_%%T.log" 2>&1
  call "%XILINX_ROOT%\Vitis\bin\vitis-run.bat" --mode hls --package --config "D:\Thesis\ThesisA\hls_component\ip_%%T.cfg" --work_dir fk_ip_%%T > "D:\Thesis\ThesisA\lpc_decoder_v2\pkg_%%T.log" 2>&1
  if exist "fk_ip_%%T\hls\impl\ip\component.xml" (
    if exist "D:\Thesis\ThesisA\fpga_kcu116\ip_repo\%%T" rmdir /s /q "D:\Thesis\ThesisA\fpga_kcu116\ip_repo\%%T"
    xcopy /e /i /q /y "fk_ip_%%T\hls\impl\ip" "D:\Thesis\ThesisA\fpga_kcu116\ip_repo\%%T" >nul
    echo packaged %%T >> "%ST%"
  ) else ( echo IP FAILED %%T >> "%ST%" )
)
echo [vivado] lpc_full %DATE% %TIME% >> "%ST%"
call D:\Thesis\ThesisA\fpga_kcu116\vivado\build.bat lpc ddr4_sdram_075 4 1 > D:\Thesis\ThesisA\lpc_decoder_v2\vivado_lpc_full.log 2>&1
echo vivado done %DATE% %TIME% >> "%ST%"
cd /d D:\Thesis\ThesisA\lpc_decoder_v2
call "%XILINX_ROOT%\Vivado\bin\vivado.bat" -mode batch -nojournal -nolog -source hier_lpc_full.tcl > hier.log 2>&1
call D:\Thesis\ThesisA\fpga_kcu116\sw\build_sw.bat lpc_full > D:\Thesis\ThesisA\lpc_decoder_v2\sw_lpc_full.log 2>&1
echo DONE %DATE% %TIME% >> "%ST%"
