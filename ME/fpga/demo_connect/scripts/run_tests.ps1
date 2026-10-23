$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
  if (-not (Get-Command iverilog -ErrorAction SilentlyContinue)) { throw 'iverilog is not installed or not in PATH.' }
  iverilog -g2012 -DSIMULATION -s tb_udp_echo_rgmii -o tb\udp_echo.vvp tb\tb_udp_echo_rgmii.v src\rgmii_100_deserializer.v src\rgmii_frame_adapter.v src\rtl8211f_mdio_init.v src\udp_ping_rx.v src\gowin_pll_50m_to_25m.v src\rgmii_100_ack_tx_pll.v src\top_acg525_udp_echo.v
  $simulationOutput = & vvp tb\udp_echo.vvp 2>&1
  $simulationOutput | Write-Host
  if ($LASTEXITCODE -ne 0 -or ($simulationOutput -notmatch 'UDP_ECHO_RGMII_PASS')) {
    throw "RTL testbench did not pass."
  }
} finally { Remove-Item tb\udp_echo.vvp -ErrorAction SilentlyContinue; Pop-Location }
