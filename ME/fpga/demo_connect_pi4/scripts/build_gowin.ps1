param(
    [string]$GowinShell = "D:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $ProjectRoot
try {
    & $GowinShell ".\build_gowin.tcl"
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
