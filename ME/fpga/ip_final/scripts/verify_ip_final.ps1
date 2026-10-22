param()
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $root
try {
  $deps = Get-ChildItem .\src\deps\*.v | ForEach-Object FullName
  $local = Get-ChildItem .\src\*.v | ForEach-Object FullName
  iverilog -g2012 -DSIMULATION -s top_acg525_inline_ids -o (Join-Path $env:TEMP 'ip_final_lint.vvp') @deps @local
  if ($LASTEXITCODE -ne 0) { throw 'RTL elaboration failed.' }
  & .\tb\run_resource_tb.ps1
  if ($LASTEXITCODE -ne 0) { throw 'Resource regression failed.' }
  $words = @(Get-Content .\model\node_rom.mem | Where-Object { $_.Trim() })
  if ($words.Count -ne 1273) { throw "Expected 1273 model words, found $($words.Count)." }
  Write-Host 'IP_FINAL_VERIFY_PASS'
} finally { Pop-Location }
