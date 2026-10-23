$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$gw = 'D:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe'
Push-Location $root
try {
  & $gw build_demo_no_mdio.tcl
  if ($LASTEXITCODE -ne 0) { throw "Gowin no-MDIO build failed: $LASTEXITCODE" }
  $fs = Join-Path $root 'impl\pnr\demo_no_mdio.fs'
  if (-not (Test-Path -LiteralPath $fs)) { throw 'No-MDIO bitstream was not created.' }
  Write-Host "DEMO_NO_MDIO_READY $fs" -ForegroundColor Green
} finally { Pop-Location }
