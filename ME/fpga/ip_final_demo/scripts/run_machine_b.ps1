param([string]$BindIP = '192.168.50.2', [int]$Expected = 100, [int]$Port = 55001)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
Push-Location $root
try {
  & .\.venv\Scripts\python.exe -m ME.sw.ethernet_test.receive_from_onboard_port --local-ip $BindIP --port $Port --expected $Expected
} finally { Pop-Location }

