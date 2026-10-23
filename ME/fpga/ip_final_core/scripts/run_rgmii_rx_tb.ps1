$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $root
try {
  $out=Join-Path $env:TEMP 'tb_rgmii_rx_byte.vvp'
  iverilog -g2012 -DSIMULATION -s tb_rgmii_rx_byte -o $out .\src\rgmii_rx_byte.v .\tb\tb_rgmii_rx_byte.v
  if($LASTEXITCODE -ne 0){throw 'RGMII RX testbench compilation failed'}
  vvp $out
  if($LASTEXITCODE -ne 0){throw 'RGMII RX testbench failed'}
} finally { Pop-Location }
