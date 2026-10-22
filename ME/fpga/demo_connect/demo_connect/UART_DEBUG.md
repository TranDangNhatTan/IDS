# UART debug for the ACG525 Ethernet bridge

The debug transmitter uses the ACG525 onboard UART TX signal:

- FPGA pin: `V8`
- I/O standard: `LVCMOS33`
- format: `115200 baud, 8 data bits, no parity, 1 stop bit`
- output: `DBG=hhhh` once per second

Use the board UART connector or a 3.3 V USB-to-UART adapter. Connect FPGA TX
to adapter RX and connect GND to GND. Do not connect an RS-232 voltage-level
port directly to the FPGA.

`hhhh` is a sticky 16-bit status word. A bit remains one until FPGA reset:

| Bit | Mask | Meaning |
|---:|---:|---|
| 0 | `0001` | onboard PHY reset completed |
| 1 | `0002` | RTL8211F MDIO write sequence completed |
| 2 | `0004` | LAN8720 50 MHz REF_CLK observed |
| 3 | `0008` | LAN8720 CRS_DV asserted |
| 4 | `0010` | a byte was decoded from LAN8720 RMII |
| 5 | `0020` | a complete LAN8720 RX frame was committed |
| 6 | `0040` | onboard RGMII transmitter became active |
| 7 | `0080` | onboard RTL8211F RX_CTL asserted |
| 8 | `0100` | a byte was decoded from onboard RGMII |
| 9 | `0200` | a complete onboard RGMII RX frame was committed |
| 10 | `0400` | LAN8720 TX_EN asserted |
| 11 | `0800` | RMII receive alignment error |
| 12 | `1000` | RGMII receive alignment error |
| 13 | `2000` | either packet FIFO overflowed |
| 14 | `4000` | either transmitter underflowed |
| 15 | `8000` | reserved |

After startup with no Ethernet traffic, a healthy base value is normally
`DBG=0007`: reset complete, MDIO sequence complete, and LAN8720 REF_CLK alive.

Run the native Windows decoder from PowerShell:

```powershell
Get-CimInstance Win32_SerialPort | Format-Table DeviceID,Name
powershell -ExecutionPolicy Bypass -File .\tools\read_uart_debug.ps1 -Port COM5
```

Replace `COM5` with the port shown by Device Manager or the first command.
When machine A sends a packet toward machine B, bits 3, 4, 5, and 6 should
become one. When machine B sends toward machine A, bits 7, 8, 9, and 10 should
become one.

The UART unit test is:

```bat
run_uart_icarus.bat
```

The build output and stable copy are generated at:

```text
impl/pnr/demo_connect_release.fs
release/demo_connect_uart_debug.fs
```
