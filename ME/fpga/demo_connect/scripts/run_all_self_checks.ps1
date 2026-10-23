$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
& (Join-Path $PSScriptRoot 'run_tests.ps1')
& (Join-Path $PSScriptRoot 'run_udp_check.ps1') -SelfTest
Write-Host 'ALL_DEMO_CONNECT_SELF_CHECKS_PASS' -ForegroundColor Green
