$ErrorActionPreference='Stop';$root=Split-Path -Parent $PSScriptRoot;$gw='D:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe'
Push-Location $root
try { & $gw build_gigabit_clock_diag.tcl;if($LASTEXITCODE -ne 0){throw "Gowin Gigabit PLL build failed: $LASTEXITCODE"};$fs=Join-Path $root 'impl\pnr\gigabit_clock_diag.fs';if(!(Test-Path -LiteralPath $fs)){throw 'Gigabit diagnostic bitstream was not created.'};Write-Host "GIGABIT_CLOCK_DIAG_READY $fs" -ForegroundColor Green } finally { Pop-Location }
