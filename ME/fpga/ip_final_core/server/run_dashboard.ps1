param(
    [int]$HttpPort = 8081,
    [int]$ResultPort = 55003
)
$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Write-Host "Starting LAN-only FPGA IDS dashboard: http://127.0.0.1:$HttpPort" -ForegroundColor Cyan
Write-Host "UDP result receiver is bound to port $ResultPort" -ForegroundColor Cyan
& python (Join-Path $scriptDir "ids_core_server.py") --http-port $HttpPort --result-port $ResultPort
