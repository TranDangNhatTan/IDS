param([int]$Port = 55003)
# Sends the exact UDP DBG1 payload emitted by the FPGA trace engine to the
# local dashboard listener.  It isolates the web server/Windows UDP receive
# path from the FPGA and Ethernet cable.
$payload = [byte[]](0x44,0x42,0x47,0x31,
                    0x00,0x00,0x00,0x01,
                    0x00,0x00,0x00,0x02,
                    0x00,0x00,0x00,0x03,
                    0x00,0x00,0x00,0x04,
                    0x00,0x00,0x00,0x05)
$client = [System.Net.Sockets.UdpClient]::new()
try {
  [void]$client.Send($payload, $payload.Length, '127.0.0.1', $Port)
  Write-Host "DBG1 self-test sent to 127.0.0.1:$Port. Refresh dashboard; expect fpga_trace frames=1 ipv4=2 ip_udp=3 dst_port=4 magic=5."
} finally {
  $client.Dispose()
}
