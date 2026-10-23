param([string]$Target='192.168.50.255',[int]$Count=10,[int]$Port=55002,[int]$ReplyPort=55003,[switch]$SelfTest)
$ErrorActionPreference='Stop'
$script=Join-Path $PSScriptRoot 'udp_ping_check.py'
if ($SelfTest) { python $script --self-test } else { python $script --target $Target --port $Port --reply-port $ReplyPort --count $Count }
