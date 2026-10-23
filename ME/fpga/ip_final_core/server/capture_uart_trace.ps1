param(
 [string]$Port = 'COM13',
 [int]$Seconds = 75,
 [string]$LogFile = ''
)
$ErrorActionPreference = 'Stop'
if($Seconds -lt 1){ throw 'Seconds must be positive.' }
if([string]::IsNullOrWhiteSpace($LogFile)){
 $LogFile = Join-Path $PSScriptRoot ("uart_trace_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
}
$serial = [System.IO.Ports.SerialPort]::new($Port,115200,'None',8,'One')
$serial.NewLine = "`n"
$serial.ReadTimeout = 250
try {
 $serial.Open()
 Write-Host "UART_TRACE listening $Port at 115200 8-N-1 for $Seconds s"
 Write-Host "Log file: $LogFile"
 $until = (Get-Date).AddSeconds($Seconds)
 while((Get-Date) -lt $until){
  try {
   $line = $serial.ReadLine().Trim("`r","`n")
   if($line){
    $shown = "[{0:HH:mm:ss}] {1}" -f (Get-Date),$line
    $shown | Tee-Object -FilePath $LogFile -Append
   }
  } catch [System.TimeoutException] {}
 }
} finally {
 if($serial.IsOpen){$serial.Close()}
 $serial.Dispose()
}
