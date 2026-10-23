param(
    [int]$HttpPort = 8081,
    [int]$ResultPort = 55003,
    [switch]$Restart
)
$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$serverPath = (Join-Path $scriptDir "ids_core_server.py")

# A previous foreground PowerShell window may have been closed while Python
# stayed alive. Detect only this project's server; never terminate an
# unrelated application which happens to use one of the requested ports.
$listeners = @()
$listeners += @(Get-NetUDPEndpoint -LocalPort $ResultPort -ErrorAction SilentlyContinue)
$listeners += @(Get-NetTCPConnection -LocalPort $HttpPort -State Listen -ErrorAction SilentlyContinue)
$ownerPids = @($listeners | ForEach-Object { $_.OwningProcess } | Where-Object { $_ } | Sort-Object -Unique)
$ourServers = @()
$foreignOwners = @()
foreach ($ownerPid in $ownerPids) {
    $owner = Get-CimInstance Win32_Process -Filter "ProcessId=$ownerPid" -ErrorAction SilentlyContinue
    if ($owner -and $owner.CommandLine -and
        $owner.CommandLine.IndexOf($serverPath, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
        $ourServers += $owner
    } elseif ($owner) {
        $foreignOwners += $owner
    }
}

if ($foreignOwners.Count -gt 0) {
    $details = ($foreignOwners | ForEach-Object { "PID $($_.ProcessId) ($($_.Name))" }) -join ", "
    throw "Port $HttpPort or UDP $ResultPort is occupied by another application: $details"
}

if ($ourServers.Count -gt 0) {
    if (-not $Restart) {
        $pidText = ($ourServers.ProcessId | Sort-Object -Unique) -join ", "
        Write-Host "DASHBOARD_ALREADY_RUNNING: http://127.0.0.1:$HttpPort (PID $pidText)" -ForegroundColor Green
        Write-Host "Use -Restart only when you want to clear and restart the server process." -ForegroundColor Yellow
        exit 0
    }
    foreach ($server in $ourServers) {
        Stop-Process -Id $server.ProcessId -Force
        Write-Host "Stopped previous dashboard PID $($server.ProcessId)." -ForegroundColor Yellow
    }
    Start-Sleep -Milliseconds 500
}

Write-Host "Starting LAN-only FPGA IDS dashboard: http://127.0.0.1:$HttpPort" -ForegroundColor Cyan
Write-Host "UDP result receiver is bound to port $ResultPort" -ForegroundColor Cyan
& python $serverPath --http-port $HttpPort --result-port $ResultPort
