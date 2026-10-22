@echo off
setlocal
cd /d "%~dp0"

echo ============================================================
echo MACHINE B - RECEIVE FROM ACG525 ONBOARD RJ45
echo Local  : 192.168.50.2:55001
echo Expect : 100 packets
echo Keep this window open, then start machine A.
echo ============================================================

where py >nul 2>nul
if not errorlevel 1 (
  py -3 machine_b_receiver.py --local-ip 192.168.50.2 --port 55001 --expected 100 --idle-timeout 5 %*
) else (
  python machine_b_receiver.py --local-ip 192.168.50.2 --port 55001 --expected 100 --idle-timeout 5 %*
)

echo.
pause
endlocal
