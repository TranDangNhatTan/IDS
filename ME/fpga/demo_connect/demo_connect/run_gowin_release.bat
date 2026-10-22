@echo off
setlocal
cd /d "%~dp0"
if not exist src\demo_connect.cst exit /b 2
set "GOWIN_SH=D:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe"
if not exist "%GOWIN_SH%" (
  echo ERROR: gw_sh.exe not found at %GOWIN_SH%
  exit /b 1
)
"%GOWIN_SH%" build_gowin_release.tcl
if errorlevel 1 exit /b 1
if not exist "impl\pnr\demo_connect_release.fs" (
  echo ERROR: expected bitstream was not generated.
  exit /b 3
)
if not exist release mkdir release
copy /y "impl\pnr\demo_connect_release.fs" "release\demo_connect_uart_debug.fs" >nul
echo RELEASE_BITSTREAM: release\demo_connect_uart_debug.fs
endlocal
