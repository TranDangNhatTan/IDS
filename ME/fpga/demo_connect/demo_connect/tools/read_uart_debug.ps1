param(
    [Parameter(Mandatory = $true)]
    [string]$Port,
    [switch]$ShowAll
)

$serial = [System.IO.Ports.SerialPort]::new(
    $Port,
    115200,
    [System.IO.Ports.Parity]::None,
    8,
    [System.IO.Ports.StopBits]::One
)
$serial.Handshake = [System.IO.Ports.Handshake]::None
$serial.NewLine = "`n"
$serial.ReadTimeout = 2000
$previous = $null

function Show-Flag([int]$Value, [int]$Bit, [string]$Name) {
    $set = ($Value -band (1 -shl $Bit)) -ne 0
    Write-Host ("  bit {0,2} {1,-25}: {2}" -f $Bit, $Name, [int]$set)
}

try {
    $serial.Open()
    Write-Host "Listening on $Port at 115200 baud, 8-N-1. Press Ctrl+C to stop."
    while ($true) {
        try {
            $line = $serial.ReadLine().Trim()
        } catch [System.TimeoutException] {
            continue
        }

        if ($line -notmatch '^DBG=([0-9A-Fa-f]{4})$') {
            Write-Host "RAW: $line"
            continue
        }

        $value = [Convert]::ToInt32($Matches[1], 16)
        if ($ShowAll -or $null -eq $previous -or $value -ne $previous) {
            Write-Host ""
            Write-Host ("{0:HH:mm:ss.fff} {1}" -f (Get-Date), $line)
            Show-Flag $value 0  "PHY reset complete"
            Show-Flag $value 1  "MDIO writes complete"
            Show-Flag $value 2  "LAN8720 REF_CLK alive"
            Show-Flag $value 3  "LAN8720 CRS_DV seen"
            Show-Flag $value 4  "LAN8720 RX byte seen"
            Show-Flag $value 5  "LAN8720 RX frame seen"
            Show-Flag $value 6  "RTL8211F RGMII TX seen"
            Show-Flag $value 7  "RTL8211F RX_CTL seen"
            Show-Flag $value 8  "RTL8211F RX byte seen"
            Show-Flag $value 9  "RTL8211F RX frame seen"
            Show-Flag $value 10 "LAN8720 TX_EN seen"
            Show-Flag $value 11 "RMII RX alignment error"
            Show-Flag $value 12 "RGMII RX alignment error"
            Show-Flag $value 13 "FIFO overflow"
            Show-Flag $value 14 "TX underflow"
        }
        $previous = $value
    }
} finally {
    if ($serial.IsOpen) {
        $serial.Close()
    }
    $serial.Dispose()
}
