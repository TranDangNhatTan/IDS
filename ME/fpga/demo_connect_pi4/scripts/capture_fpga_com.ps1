param(
    [Parameter(Mandatory=$true)][string]$ComPort,
    [int]$Baud = 115200,
    [int]$TimeoutSeconds = 10,
    [string]$Expected = "55 AA 00 FF A5 5A"
)

$ErrorActionPreference = "Stop"
$expectedBytes = @($Expected -split '\s+' | ForEach-Object { [Convert]::ToByte($_,16) })
$port = [System.IO.Ports.SerialPort]::new($ComPort,$Baud,[System.IO.Ports.Parity]::None,8,[System.IO.Ports.StopBits]::One)
$port.Handshake = [System.IO.Ports.Handshake]::None
$port.ReadTimeout = 100
$port.DtrEnable = $false
$port.RtsEnable = $false

$received = [System.Collections.Generic.List[byte]]::new()
try {
    try {
        $port.Open()
    }
    catch [System.UnauthorizedAccessException] {
        Write-Error "COM_BUSY: $ComPort is already open. Close PuTTY/Arduino serial monitor/dashboard, then retry."
        exit 2
    }
    catch {
        Write-Error "COM_OPEN_FAIL: cannot open $ComPort - $($_.Exception.Message)"
        exit 2
    }
    $port.DiscardInBuffer()
    Write-Host "COM=$ComPort opened at $Baud 8N1. Start the Pi transmitter now."
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline -and $received.Count -lt $expectedBytes.Count) {
        while ($port.BytesToRead -gt 0 -and $received.Count -lt $expectedBytes.Count) {
            $b = [byte]$port.ReadByte()
            $received.Add($b)
            Write-Host ("[{0}] RX index={1} value=0x{2:X2}" -f (Get-Date -Format "HH:mm:ss.fff"),($received.Count-1),$b)
        }
        Start-Sleep -Milliseconds 10
    }
}
finally {
    if ($port.IsOpen) { $port.Close() }
}

$expText = ($expectedBytes | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
$rxText = ($received | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
Write-Host "EXPECTED=$expText"
Write-Host "RECEIVED=$rxText"
if ($received.Count -ne $expectedBytes.Count) {
    Write-Error "RESULT=FAIL reason=timeout expected=$($expectedBytes.Count) received=$($received.Count)"
    exit 1
}
for ($i=0; $i -lt $expectedBytes.Count; $i++) {
    if ($received[$i] -ne $expectedBytes[$i]) {
        Write-Error ("RESULT=FAIL reason=byte_mismatch index={0} expected=0x{1:X2} got=0x{2:X2}" -f $i,$expectedBytes[$i],$received[$i])
        exit 1
    }
}
Write-Host "RESULT=PASS"
