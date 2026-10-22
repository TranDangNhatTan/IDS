@echo off
setlocal
cd /d "%~dp0..\.."

if not exist ".venv\Scripts\python.exe" (
  echo ERROR: Cannot find .venv\Scripts\python.exe
  echo Run this file from the FPGA_MCU_IDS repository package.
  pause
  exit /b 2
)

echo ============================================================
echo MACHINE A - SEND THROUGH EXTERNAL LAN8720
echo Local    : 192.168.50.22
echo Receiver : 192.168.50.11:55001
echo Test     : 100 packets at 1 Mbps
echo Start RUN_MACHINE_B.bat on machine B first.
echo ============================================================

".venv\Scripts\python.exe" -m ME.sw.ethernet_test.send_to_external_module ^
  --local-ip 192.168.50.22 ^
  --receiver-ip 192.168.50.11 ^
  --port 55001 ^
  --count 100 ^
  --payload-size 1400 ^
  --rate-mbps 1 %*

echo.
pause
endlocal
