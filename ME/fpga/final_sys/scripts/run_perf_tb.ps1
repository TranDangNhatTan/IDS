$ErrorActionPreference='Stop';$root=Split-Path -Parent $PSScriptRoot;Push-Location $root
try {
  iverilog -g2012 -DSIMULATION -s tb_perf -o .\tb_perf.vvp .\tb\tb_perf.sv .\src\uart_tx_sync.v .\src\result_frame_tx.v ..\ip_final\src\ids_tree_rom_banked.v ..\ip_final\src\ids_tree_engine_live.v ..\ip_final\src\deps\ids_node_decoder.v ..\ip_final\src\deps\ids_feature_regfile.v
  if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}; vvp .\tb_perf.vvp
} finally {Pop-Location}
