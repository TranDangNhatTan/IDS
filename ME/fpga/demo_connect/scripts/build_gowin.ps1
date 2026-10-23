$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$candidates = @()
if ($env:GOWIN_HOME) { $candidates += Join-Path $env:GOWIN_HOME 'IDE\bin\gw_sh.exe' }
$candidates += 'D:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe'
$candidates = @($candidates | Where-Object { Test-Path $_ })
if (-not $candidates) { throw 'Cannot find gw_sh.exe. Set GOWIN_HOME to the Gowin installation directory.' }
Push-Location $root
try {
  & $candidates[0] build_gowin.tcl
  if ($LASTEXITCODE -ne 0) { throw "Gowin build failed with exit code $LASTEXITCODE" }
  $fs = Join-Path $root 'impl\pnr\demo_connect.fs'
  if (-not (Test-Path $fs)) { throw 'Gowin completed but did not create impl\pnr\demo_connect.fs.' }
  Write-Host "BITSTREAM_READY $fs" -ForegroundColor Green
} finally { Pop-Location }
