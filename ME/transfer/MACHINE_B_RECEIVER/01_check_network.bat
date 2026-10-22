@echo off
cd /d "%~dp0"
where py >nul 2>nul
if not errorlevel 1 (
  py -3 check_machine_b.py %*
) else (
  python check_machine_b.py %*
)
pause
