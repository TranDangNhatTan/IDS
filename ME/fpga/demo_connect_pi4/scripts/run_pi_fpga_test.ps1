param(
    [string]$Config = "$PSScriptRoot\..\connection.json"
)

$ErrorActionPreference = "Stop"
$cfg = Get-Content -LiteralPath $Config -Raw | ConvertFrom-Json
$expected = @($cfg.TestValues | ForEach-Object { [Convert]::ToByte($_, 16) })
$sshTarget = "$($cfg.PiUser)@$($cfg.PiHost)"
$remote = "cd '$($cfg.PiProjectDir)' && python3 demo_rpi4/uart_tx_pi.py --values '$($cfg.TestValues -join ',')' --interval $($cfg.IntervalSeconds)"

Write-Host "Checking Pi $sshTarget ..."
if (-not (Test-Connection -ComputerName $cfg.PiHost -Count 1 -Quiet)) {
    throw "Pi is not reachable by ping: $($cfg.PiHost)"
}

$port = [System.IO.Ports.SerialPort]::new(
    $cfg.WindowsCom, [int]$cfg.Baud,
    [System.IO.Ports.Parity]::None, 8,
    [System.IO.Ports.StopBits]::One)
$port.Handshake = [System.IO.Ports.Handshake]::None
$port.ReadTimeout = 100
$port.Open()

$psi = [System.Diagnostics.ProcessStartInfo]::new()
$psi.FileName = "ssh.exe"
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
$psi.ArgumentList.Add("-o"); $psi.ArgumentList.Add("BatchMode=yes")
$psi.ArgumentList.Add($sshTarget)
$psi.ArgumentList.Add($remote)
$ssh = [System.Diagnostics.Process]::new()
$ssh.StartInfo = $psi
$null = $ssh.Start()

$received = [System.Collections.Generic.List[byte]]::new()
$deadline = [DateTime]::UtcNow.AddSeconds([double]$cfg.TimeoutSeconds)
try {
    while (([DateTime]::UtcNow -lt $deadline) -and $received.Count -lt $expected.Count) {
        while ($port.BytesToRead -gt 0) {
            $b = [byte]$port.ReadByte()
            $received.Add($b)
            Write-Host ("RX index={0} value=0x{1:X2}" -f ($received.Count - 1), $b)
        }
        Start-Sleep -Milliseconds 10
    }
}
finally {
    if ($port.IsOpen) { $port.Close() }
    if (-not $ssh.HasExited) { $ssh.Kill() }
}

if ($received.Count -ne $expected.Count) {
    Write-Error "FPGA_FORWARD_FAIL expected=$($expected.Count) received=$($received.Count)"
    exit 1
}
for ($i = 0; $i -lt $expected.Count; $i++) {
    if ($received[$i] -ne $expected[$i]) {
        Write-Error ("FPGA_FORWARD_FAIL index={0} expected=0x{1:X2} got=0x{2:X2}" -f $i,$expected[$i],$received[$i])
        exit 1
    }
}
Write-Host "PI_REACHABLE=PASS"
Write-Host "WINDOWS_COM_OPEN=PASS"
Write-Host "FPGA_FORWARD_PASS TX_COUNT=$($expected.Count) RX_COUNT=$($received.Count)"
Write-Host "RESULT=PASS"
exit 0
