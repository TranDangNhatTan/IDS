@echo off
setlocal
cd /d "%~dp0"
set "GOWIN_SH=D:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe"
if not exist "%GOWIN_SH%" (
  echo ERROR: gw_sh.exe not found at %GOWIN_SH%
  exit /b 1
)
"%GOWIN_SH%" build_gowin.tcl
endlocal
