param(
  [string]$Adapter = 'Ethernet',
  [int]$HttpPort = 8081,
  [int]$ResultPort = 55003
)
# One-command clean dashboard restart and local receive-path validation.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$server = Join-Path $root 'server\ids_core_server.py'

$nic = Get-NetAdapter -Name $Adapter
if ($nic.Status -ne 'Up') {
  throw "Adapter '$Adapter' is $($nic.Status), not Up. Connect board Ethernet before running the LAN test."
}
Write-Host "Ethernet: $($nic.Status), $($nic.LinkSpeed)" -ForegroundColor Green

# Only stop the process currently owning the dashboard UDP result port.
$old = Get-NetUDPEndpoint -LocalPort $ResultPort -ErrorAction SilentlyContinue | Select-Object -First 1
if ($old) {
  $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$($old.OwningProcess)"
  if ($proc.CommandLine -match 'ids_core_server\.py') {
    Stop-Process -Id $old.OwningProcess -Force
    Start-Sleep -Milliseconds 400
    Write-Host "Stopped previous dashboard process $($old.OwningProcess)." -ForegroundColor Yellow
  } else {
    throw "UDP $ResultPort is owned by process $($old.OwningProcess), not the IDS dashboard. Close it first."
  }
}

$py = (Get-Command python -ErrorAction Stop).Source
Start-Process -FilePath $py -ArgumentList @($server, '--http-port', $HttpPort, '--result-port', $ResultPort) -WorkingDirectory $root -WindowStyle Hidden
Start-Sleep -Seconds 2

$listener = Get-NetUDPEndpoint -LocalPort $ResultPort -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $listener) { throw "Dashboard did not bind UDP $ResultPort." }

# Local DBG1 packet proves browser server + Windows UDP receive path first.
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'server\test_dashboard_rx.ps1') -Port $ResultPort

$url = "http://127.0.0.1:$HttpPort"
Start-Process $url
Write-Host "READY: $url" -ForegroundColor Cyan
Write-Host 'Refresh once; LAN event log must show fpga_trace frames=1 ipv4=2 ip_udp=3 dst_port=4 magic=5.' -ForegroundColor Cyan
