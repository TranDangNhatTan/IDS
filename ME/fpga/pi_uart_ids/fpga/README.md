# Pi UART IDS FPGA v2

This standalone Gowin project implements Protocol Contract v2 in the parent
directory. It receives model/control/FEATURE frames from the Raspberry Pi on a
full-duplex UART and returns ACK/STATUS/RESULT frames on the same UART link.

## Program

Program `release/pi_uart_ids.fs` into `GW5A-LV25UG324C2/I1` with Gowin
Programmer. Do not use the older `pi_uart_ids.fs` outside this `fpga/release`
directory or any `final_pi4_uart_rx.fs`; those images do not implement v2.

## Wiring

| Raspberry Pi 4 | ACG525 P6 / FPGA |
| --- | --- |
| GPIO14 / TXD0, physical pin 8 | P6-GPIO0, FPGA `C17` (`uart_pi_rx`) |
| GPIO15 / RXD0, physical pin 10 | P6-GPIO3, FPGA `G14` (`uart_pi_tx`) |
| GND, physical pin 6 | ACG525 GND |

Use 3.3-V TTL UART only, 115200 baud, 8N1, no flow control. Never connect
5 V or RS-232 voltage levels. TX and RX are crossed as shown.

## LEDs

The carrier LEDs are driven from `D14`, `C14`, `B9`, `A9`. If the carrier uses
active-low LEDs, the visual on/off state is inverted.

* LED0: heartbeat, toggling every roughly 0.67 s after configuration. This is
  the first proof that the programmed image and the 50 MHz clock are running.
* LED1: raw level of B16. It is diagnostic only; B16 cannot hold the FPGA core
  in reset.
* LED2: a MODEL_COMMIT with valid 1273-word image CRC was accepted, or at least
  one valid 77-byte FEATURE was accepted.
* LED3: sticky UART/COBS/CRC/length/version/parser/FIFO/upload error.

## Build evidence

Run `scripts/build_gowin.ps1`. The final v2 implementation completed with
zero setup violations, zero hold violations and an actual Fmax of 75.113 MHz
against the 50 MHz constraint. It uses 52 of 56 BSRAMs: two explicit model
banks preserve the active model during a rejected upload.
