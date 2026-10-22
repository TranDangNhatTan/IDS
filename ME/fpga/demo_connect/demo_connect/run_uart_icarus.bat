@echo off
setlocal
cd /d "%~dp0"
if not exist impl mkdir impl
iverilog -g2005 -Wall -s tb_uart_debug_reporter -o impl\tb_uart_debug_reporter.vvp ^
  src\uart_tx_byte.v ^
  src\uart_debug_reporter.v ^
  tb\tb_uart_debug_reporter.v
if errorlevel 1 exit /b 1
vvp impl\tb_uart_debug_reporter.vvp
endlocal
