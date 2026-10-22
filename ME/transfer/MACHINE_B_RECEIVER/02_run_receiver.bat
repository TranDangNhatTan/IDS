@echo off
cd /d "%~dp0"
where py >nul 2>nul
if not errorlevel 1 (
  py -3 machine_b_receiver.py %*
) else (
  python machine_b_receiver.py %*
)
pause
