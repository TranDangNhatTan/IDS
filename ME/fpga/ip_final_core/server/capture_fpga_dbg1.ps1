param([int]$Seconds=6,[int]$Port=55003,[switch]$StopDashboard)
$ErrorActionPreference='Stop'
if($StopDashboard) {
  $servers=Get-CimInstance Win32_Process -Filter "name='python.exe'" |
    Where-Object { $_.CommandLine -match 'ids_core_server\.py' }
  foreach($server in $servers) {
    Stop-Process -Id $server.ProcessId -Force
    Write-Host "Stopped dashboard process $($server.ProcessId)."
  }
  Start-Sleep -Milliseconds 300
}
try {
  $udp=[System.Net.Sockets.UdpClient]::new($Port)
} catch {
  throw "Cannot bind UDP $Port. Stop run_dashboard.ps1 first with Ctrl+C, then run this script. $($_.Exception.Message)"
}
try {
  $udp.Client.ReceiveTimeout=250
  $until=(Get-Date).AddSeconds($Seconds)
  $count=0
  Write-Host "Listening on UDP $Port for $Seconds s; expected FPGA source 192.168.50.50 and payload DBG1."
  while((Get-Date) -lt $until) {
    try {
      $remote=[System.Net.IPEndPoint]::new([System.Net.IPAddress]::Any,0)
      $bytes=$udp.Receive([ref]$remote)
      $text=[Text.Encoding]::ASCII.GetString($bytes)
      $magic=if($text.Length -ge 4){$text.Substring(0,4)}else{$text}
      $count++
      Write-Host "RX source=$($remote.Address):$($remote.Port) bytes=$($bytes.Length) magic=$magic"
    } catch [System.Net.Sockets.SocketException] { }
  }
  if($count -eq 0){Write-Host 'NO_UDP_RECEIVED: FPGA TX did not reach the laptop on UDP 55003.'}
  else {Write-Host "UDP_CAPTURE_PASS packets=$count"}
} finally { $udp.Dispose() }
