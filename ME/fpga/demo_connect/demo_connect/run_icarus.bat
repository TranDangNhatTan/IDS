@echo off
setlocal
cd /d "%~dp0"
if not exist impl mkdir impl
iverilog -g2005 -Wall -s tb_rgmii_rmii_bridge -o impl\tb_rgmii_rmii_bridge.vvp ^
  src\reset_sync.v ^
  src\rtl8211f_mdio_init.v ^
  src\rmii_deserializer.v ^
  src\rmii_serializer.v ^
  src\async_packet_fifo.v ^
  src\rgmii_100_deserializer.v ^
  src\rgmii_100_serializer.v ^
  src\uart_tx_byte.v ^
  src\uart_debug_reporter.v ^
  src\top_acg525_rgmii_rmii_bridge.v ^
  tb\tb_rgmii_rmii_bridge.v
if errorlevel 1 exit /b 1
vvp impl\tb_rgmii_rmii_bridge.vvp
endlocal
