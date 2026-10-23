#Requires -Version 5.1
<#
.SYNOPSIS
    Launches the IDS Traffic Generator web dashboard.
.DESCRIPTION
    Starts the Flask web server for the Laptop B traffic generator dashboard.
    Run this script with Administrator privileges for raw packet sending.
#>

Set-Location $PSScriptRoot

Write-Host ""
Write-Host "  =======================================" -ForegroundColor Cyan
Write-Host "    IDS Traffic Generator — Laptop B"     -ForegroundColor Cyan
Write-Host "    Starting Web Dashboard..."            -ForegroundColor Cyan
Write-Host "  =======================================" -ForegroundColor Cyan
Write-Host ""

# Check admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) {
    Write-Host "  [WARNING] Not running as Administrator." -ForegroundColor Yellow
    Write-Host "            Raw packet sending may fail."   -ForegroundColor Yellow
    Write-Host "            Run PowerShell as Admin and re-run this script." -ForegroundColor Yellow
    Write-Host ""
}

# Check Python
try {
    $null = & python --version 2>&1
} catch {
    Write-Host "  [ERROR] Python not found in PATH." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

# Install requirements if needed
$scapyCheck = pip show scapy 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "  Installing dependencies..." -ForegroundColor Yellow
    & pip install -r requirements.txt
}

Write-Host "  Starting web server on http://127.0.0.1:5000 ..." -ForegroundColor Green
Write-Host ""

& python app.py

Read-Host "Press Enter to exit"
