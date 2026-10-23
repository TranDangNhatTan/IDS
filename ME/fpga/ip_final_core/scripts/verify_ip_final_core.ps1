$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
function Run-Tb([string]$Top,[string[]]$Files) {
  $out=Join-Path $env:TEMP ($Top+'.vvp')
  & iverilog -g2012 -DSIMULATION -s $Top -o $out @Files
  if($LASTEXITCODE -ne 0){throw "$Top compilation failed"}
  & vvp $out
  if($LASTEXITCODE -ne 0){throw "$Top failed"}
}
Push-Location $root
try {
  python -m py_compile .\server\ids_core_server.py
  if($LASTEXITCODE -ne 0){throw 'Dashboard Python syntax check failed'}

  Run-Tb 'tb_rgmii_rx_byte' @('.\tb\gowin_iddr_model.v','.\src\rgmii_rx_byte.v','.\tb\tb_rgmii_rx_byte.v')
  Run-Tb 'tb_rgmii_tx_byte' @('.\src\rgmii_tx_byte.v','.\tb\tb_rgmii_tx_byte.v')
  Run-Tb 'tb_udp_reply_tx' @('.\src\ids_udp_reply_tx.v','.\tb\tb_udp_reply_tx.v')
  Run-Tb 'tb_lan_protocol' @('.\src\ids_udp_feature_rx.v','.\tb\tb_lan_protocol.v')
  Run-Tb 'tb_udp_ftr2_rx' @('.\src\ids_udp_feature_rx.v','.\tb\tb_udp_ftr2_rx.v')
  Run-Tb 'tb_rgmii_udp_end_to_end' @('.\tb\gowin_iddr_model.v','.\src\rgmii_rx_byte.v','.\src\ids_udp_feature_rx.v','.\tb\tb_rgmii_udp_end_to_end.v')
  Run-Tb 'tb_full_model_bram' @('.\src\ids_udp_feature_rx.v','.\src\ids_tree_rom_banked.v','.\tb\tb_full_model_bram.v')
  Run-Tb 'tb_uart_trace' @('.\src\uart_tx_byte.v','.\src\ids_uart_trace.v','.\tb\tb_uart_trace.v')

  $deps=Get-ChildItem .\src\deps\*.v|ForEach-Object FullName
  $sources=Get-ChildItem .\src\*.v|ForEach-Object FullName
  & iverilog -g2012 -DSIMULATION -s top_acg525_ids_core -o (Join-Path $env:TEMP 'ip_final_core.vvp') @deps @sources .\tb\gowin_iddr_model.v .\tb\eth_rgmii_pll_sim.v
  if($LASTEXITCODE -ne 0){throw 'Top-level RTL lint failed'}
  $words=@(Get-Content .\model\node_rom.mem|Where-Object{$_.Trim()})
  if($words.Count -ne 1273){throw "Model image length incorrect: $($words.Count)"}
  Write-Host 'IP_FINAL_CORE_VERIFY_PASS: protocol, DDR RX/TX, FCS, full BRAM and UART tests passed.'
} finally {Pop-Location}
