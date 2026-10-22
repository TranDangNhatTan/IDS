$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $root
try {
 $d=Get-ChildItem .\src\deps\*.v|ForEach-Object FullName
 $s=Get-ChildItem .\src\*.v|ForEach-Object FullName
 iverilog -g2012 -DSIMULATION -s top_acg525_ids_core -o (Join-Path $env:TEMP 'ip_final_core.vvp') @d @s
 if($LASTEXITCODE -ne 0){throw 'RTL lint failed'}
 $w=@(Get-Content .\model\node_rom.mem|Where-Object{$_.Trim()})
 if($w.Count -ne 1273){throw 'Model image length incorrect'}
 Write-Host 'IP_FINAL_CORE_VERIFY_PASS'
} finally {Pop-Location}
