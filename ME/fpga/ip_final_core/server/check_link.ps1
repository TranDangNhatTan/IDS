param([string]$Adapter = 'Ethernet')
$ErrorActionPreference = 'Stop'
$net = Get-NetAdapter -Name $Adapter
$net | Format-List Name,Status,LinkSpeed,MacAddress
if ($net.Status -ne 'Up') {
    Write-Error 'Ethernet link is DOWN. Check cable, switch port and FPGA PHY reset.'
}
if ($net.LinkSpeed -ne '100 Mbps') {
    Write-Warning 'This stable RGMII IDS bitstream is configured for 100 Mbps. Ensure the link has negotiated 100 Mbps before benchmarking.'
} else {
    Write-Host 'LINK_OK: 100 Mbps RGMII benchmark may be started.' -ForegroundColor Green
}
