#Requires -Version 5.1
<#
.SYNOPSIS
    Runs the IDS Traffic Generator in CLI mode.
.DESCRIPTION
    Launches send_raw_traffic.py with any provided arguments.
    Run with Administrator privileges for raw packet sending.
.EXAMPLE
    .\run_generator.ps1 --count 50 --rate 10
    .\run_generator.ps1 --dry-run
    .\run_generator.ps1 --verify-network
#>

Set-Location $PSScriptRoot

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) {
    Write-Host "[WARNING] Not running as Administrator." -ForegroundColor Yellow
}

& python send_raw_traffic.py @args
