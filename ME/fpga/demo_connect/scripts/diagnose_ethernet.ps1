param([string]$Adapter = 'Ethernet')

$ErrorActionPreference = 'Stop'

function Section([string]$Name) {
    Write-Host "`n=== $Name ===" -ForegroundColor Cyan
}

Section 'Network adapter / physical link'
$nic = Get-NetAdapter -Name $Adapter
$nic | Format-List Name,InterfaceDescription,Status,LinkSpeed,MacAddress,MediaConnectionState,DriverName,DriverVersion

Section 'IPv4 configuration'
Get-NetIPConfiguration -InterfaceIndex $nic.ifIndex |
    Format-List InterfaceAlias,IPv4Address,IPv4DefaultGateway,NetProfile

Section 'Speed / duplex properties'
$props = Get-NetAdapterAdvancedProperty -Name $Adapter -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -match 'Speed|Duplex|Link|T[oô]c' }
if ($props) { $props | Format-Table DisplayName,DisplayValue,RegistryKeyword -AutoSize }
else { Write-Host 'Driver does not expose Speed/Duplex through PowerShell.' -ForegroundColor Yellow }

Section 'Adapter counters'
Get-NetAdapterStatistics -Name $Adapter |
    Format-List ReceivedBytes,ReceivedUnicastPackets,ReceivedDiscardedPackets,ReceivedPacketErrors,SentBytes,SentUnicastPackets,OutboundDiscardedPackets,OutboundPacketErrors

Section 'Recent link-related Windows events'
try {
    Get-WinEvent -FilterHashtable @{LogName='System'; StartTime=(Get-Date).AddMinutes(-15)} -ErrorAction Stop |
        Where-Object { $_.ProviderName -match 'e1|e2|Realtek|NDIS|Netwtw|Tcpip' -or $_.Message -match 'link|media' } |
        Select-Object -First 12 TimeCreated,ProviderName,Id,LevelDisplayName,Message |
        Format-List
} catch { Write-Host "Event log unavailable: $($_.Exception.Message)" -ForegroundColor Yellow }

Section 'Conclusion'
if ($nic.Status -ne 'Up') {
    Write-Host 'LINK IS DOWN: this is below IP/UDP/FPGA packet RTL. Check cable, switch port, PHY reset and board power first.' -ForegroundColor Red
    Write-Host 'To test 100 Mbps negotiation, first list Speed/Duplex above; then (as Administrator) force 100 Mbps Full Duplex temporarily if the driver exposes that setting.' -ForegroundColor Yellow
} else {
    Write-Host 'LINK IS UP: now run scripts/run_udp_check.ps1 to validate FPGA RGMII receive/transmit.' -ForegroundColor Green
}
