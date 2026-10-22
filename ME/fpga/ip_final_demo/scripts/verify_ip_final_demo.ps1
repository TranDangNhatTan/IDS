$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $root
try {
  $deps = Get-ChildItem .\src\deps\*.v | ForEach-Object FullName
  $local = Get-ChildItem .\src\*.v | ForEach-Object FullName
  iverilog -g2012 -DSIMULATION -s top_acg525_inline_ids -o (Join-Path $env:TEMP 'ip_final_demo_lint.vvp') @deps @local
  if ($LASTEXITCODE -ne 0) { throw 'RTL elaboration failed.' }
  iverilog -g2005-sv -o (Join-Path $env:TEMP 'history_bram_demo.vvp') .\src\deps\ids_history_window_bram.v .\tb\tb_ids_history_window_bram.v
  if ($LASTEXITCODE -ne 0) { throw 'History BRAM testbench compile failed.' }
  vvp (Join-Path $env:TEMP 'history_bram_demo.vvp')
  iverilog -g2005-sv -o (Join-Path $env:TEMP 'model_update_demo.vvp') .\src\model_update_uart.v .\tb\tb_model_update_uart.v
  if ($LASTEXITCODE -ne 0) { throw 'Model-update testbench compile failed.' }
  vvp (Join-Path $env:TEMP 'model_update_demo.vvp')
  $words = @(Get-Content .\model\node_rom.mem | Where-Object { $_.Trim() })
  if ($words.Count -ne 1273) { throw "Expected 1273 model words, found $($words.Count)." }
  Write-Host 'IP_FINAL_DEMO_VERIFY_PASS'
} finally { Pop-Location }

