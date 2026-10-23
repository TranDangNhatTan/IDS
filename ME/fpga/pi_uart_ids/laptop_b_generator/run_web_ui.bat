@echo off
title IDS Traffic Generator — Web UI
echo ========================================
echo   IDS Traffic Generator — Laptop B
echo   Starting Web Dashboard...
echo ========================================
echo.

cd /d "%~dp0"

:: Check for Admin
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [WARNING] Not running as Administrator.
    echo           Raw packet sending may fail.
    echo           Right-click this file and select "Run as administrator".
    echo.
)

:: Check Python
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Python not found in PATH.
    pause
    exit /b 1
)

:: Install requirements if needed
pip show scapy >nul 2>&1
if %errorlevel% neq 0 (
    echo Installing dependencies...
    pip install -r requirements.txt
)

echo Starting web server on http://127.0.0.1:5000 ...
echo.
python app.py
pause
