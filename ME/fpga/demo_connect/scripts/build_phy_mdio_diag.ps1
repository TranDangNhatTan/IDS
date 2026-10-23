$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$gw = 'D:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe'
if (-not (Test-Path -LiteralPath $gw)) { throw "Cannot find $gw" }
Push-Location $root
try {
  & $gw build_phy_mdio_diag.tcl
  if ($LASTEXITCODE -ne 0) { throw "Gowin PHY-MDIO diagnostic build failed: $LASTEXITCODE" }
  $fs = Join-Path $root 'impl\pnr\phy_mdio_diag.fs'
  if (-not (Test-Path -LiteralPath $fs)) { throw 'PHY-MDIO diagnostic bitstream was not created.' }
  Write-Host "PHY_MDIO_DIAG_READY $fs" -ForegroundColor Green
} finally { Pop-Location }
