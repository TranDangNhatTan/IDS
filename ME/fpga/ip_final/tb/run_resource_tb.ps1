$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..')).Path
Push-Location $root
try {
  iverilog -g2005-sv -o ME\hw\tb\history_bram.vvp `
    ME\hw\rtl\feature_ingest\ids_history_window_bram.v `
    ME\hw\tb\tb_ids_history_window_bram.v
  vvp ME\hw\tb\history_bram.vvp
  iverilog -g2005-sv -o ME\fpga\ip_final\tb\model_update.vvp `
    ME\fpga\ip_final\src\model_update_uart.v `
    ME\fpga\ip_final\tb\tb_model_update_uart.v
  vvp ME\fpga\ip_final\tb\model_update.vvp
} finally { Pop-Location }
