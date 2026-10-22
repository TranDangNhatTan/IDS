param([string]$TargetIP = '192.168.50.2', [int]$Count = 100, [int]$RateMbps = 1)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
Push-Location $root
try {
  & .\.venv\Scripts\python.exe -m ME.sw.ethernet_test.send_to_external_module --receiver-ip $TargetIP --count $Count --rate-mbps $RateMbps
} finally { Pop-Location }
