param(
    [string]$Iverilog = "D:\Downloads\iverilog\bin\iverilog.exe",
    [string]$Vvp = "D:\Downloads\iverilog\bin\vvp.exe"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$Output = Join-Path $ProjectRoot "sim\uart_forwarder_tb.vvp"

& $Iverilog -g2012 -Wall -s uart_forwarder_tb -o $Output `
    (Join-Path $ProjectRoot "src\uart_rx.v") `
    (Join-Path $ProjectRoot "src\uart_tx.v") `
    (Join-Path $ProjectRoot "src\uart_forwarder.v") `
    (Join-Path $ProjectRoot "sim\uart_forwarder_tb.sv")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $Vvp $Output
exit $LASTEXITCODE
