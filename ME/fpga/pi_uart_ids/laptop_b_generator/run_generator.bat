@echo off
title IDS Traffic Generator — CLI
echo ========================================
echo   IDS Traffic Generator — CLI Mode
echo ========================================
echo.

cd /d "%~dp0"

:: Check for Admin
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [WARNING] Not running as Administrator.
    echo.
)

python send_raw_traffic.py %*
pause
