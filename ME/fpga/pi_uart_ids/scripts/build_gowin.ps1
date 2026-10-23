param([string]$GowinShell = "D:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe")
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    & $GowinShell '.\build_gowin.tcl'
    if ($LASTEXITCODE -ne 0) { throw "Gowin build failed: exit $LASTEXITCODE" }
    Copy-Item '.\impl\pnr\pi_uart_ids.fs' '.\release\pi_uart_ids.fs' -Force
    Write-Host 'BITSTREAM=release/pi_uart_ids.fs'
} finally { Pop-Location }
