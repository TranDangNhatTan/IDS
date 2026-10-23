param(
  [string]$Report = '',
  [double]$MinSysMHz = 50.0,
  [double]$MinRxMHz = 25.0,
  [double]$MinTxLogicMHz = 25.0
)
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if(-not $Report){$Report=Join-Path $root 'impl\pnr\ip_final_core_tr_content.html'}
if(!(Test-Path -LiteralPath $Report)){throw "TIMING_FAIL: report not found: $Report"}
$html=Get-Content -LiteralPath $Report -Raw

function Get-ViolationCount([string]$Kind){
  $pattern='Numbers of '+[regex]::Escape($Kind)+' Violated Endpoints</td>\s*<td>(\d+)</td>'
  $m=[regex]::Match($html,$pattern,[Text.RegularExpressions.RegexOptions]::IgnoreCase)
  if(!$m.Success){throw "TIMING_FAIL: cannot find $Kind violation count"}
  return [int]$m.Groups[1].Value
}
function Get-Fmax([string]$Clock){
  $pattern='<td>'+[regex]::Escape($Clock)+'</td>\s*<td>[0-9.]+\(MHz\)</td>\s*<td>([0-9.]+)\(MHz\)</td>'
  $m=[regex]::Match($html,$pattern,[Text.RegularExpressions.RegexOptions]::IgnoreCase)
  if(!$m.Success){throw "TIMING_FAIL: cannot find Fmax for $Clock"}
  return [double]::Parse($m.Groups[1].Value,[Globalization.CultureInfo]::InvariantCulture)
}

$setup=Get-ViolationCount 'Setup'
$hold=Get-ViolationCount 'Hold'
$sys=Get-Fmax 'sys_clk_50'
$rx=Get-Fmax 'eth_rgmii_rx_clk'
$tx=Get-Fmax 'pll_clk_25'
if($setup -ne 0 -or $hold -ne 0){throw "TIMING_FAIL: setup=$setup hold=$hold"}
if($sys -lt $MinSysMHz){throw "TIMING_FAIL: sys_clk_50 Fmax $sys MHz < $MinSysMHz MHz"}
if($rx -lt $MinRxMHz){throw "TIMING_FAIL: eth_rgmii_rx_clk Fmax $rx MHz < $MinRxMHz MHz"}
if($tx -lt $MinTxLogicMHz){throw "TIMING_FAIL: pll_clk_25 Fmax $tx MHz < $MinTxLogicMHz MHz"}
Write-Host ("TIMING_PASS: setup={0}, hold={1}, Fmax sys={2:F3} MHz, RX={3:F3} MHz, TX={4:F3} MHz" -f $setup,$hold,$sys,$rx,$tx) -ForegroundColor Green
