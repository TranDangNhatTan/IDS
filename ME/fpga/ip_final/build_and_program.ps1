param([switch]$Program)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $root
try {
  $gowin = 'D:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe'
  if (!(Test-Path $gowin)) { throw "Gowin CLI not found: $gowin" }
  & $gowin build_gowin.tcl
  if ($LASTEXITCODE -ne 0) { throw "Gowin build failed: $LASTEXITCODE" }
  $fs = Join-Path $root 'impl\pnr\ip_final.fs'
  if (!(Test-Path $fs)) { throw "Bitstream missing: $fs" }
  New-Item -ItemType Directory -Force release | Out-Null
  Copy-Item $fs release\ip_final.fs -Force
  Get-FileHash release\ip_final.fs -Algorithm SHA256
  if ($Program) { Write-Host 'Open Gowin Programmer and program release\ip_final.fs to SRAM.' }
} finally { Pop-Location }
