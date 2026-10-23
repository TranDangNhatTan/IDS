$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
  & .\scripts\run_all_self_checks.ps1
  & .\scripts\build_gowin.ps1
  $bitstream = Join-Path $root 'impl\pnr\demo_connect.fs'
  Write-Host ''
  Write-Host 'READY_TO_PROGRAM' -ForegroundColor Green
  Write-Host $bitstream -ForegroundColor Green
  Write-Host 'Then wait 5 seconds and run:' -ForegroundColor Cyan
  Write-Host 'powershell -ExecutionPolicy Bypass -File .\scripts\run_udp_check.ps1 -Target 192.168.50.255 -Count 10 -ReplyPort 55103' -ForegroundColor Cyan
} finally {
  Pop-Location
}
