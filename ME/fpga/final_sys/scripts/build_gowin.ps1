param([string]$GowinShell="D:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\gw_sh.exe")
$ErrorActionPreference='Stop';$root=Split-Path -Parent $PSScriptRoot;Push-Location $root
try { & $GowinShell '.\build_gowin.tcl'; if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}; Copy-Item '.\impl\pnr\final_sys.fs' '.\release\final_sys.fs' -Force } finally {Pop-Location}
