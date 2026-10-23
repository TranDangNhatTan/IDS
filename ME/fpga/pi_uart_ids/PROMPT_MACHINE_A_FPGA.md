# Prompt A — FPGA implementation on the current machine

You are a senior Gowin FPGA engineer. Implement a new, standalone project at
`ME/fpga/pi_uart_ids/`. Do not modify `ME/fpga/ip_final*` or
`ME/fpga/demo_connect_pi4`.

Read and obey `PROTOCOL_CONTRACT.md` exactly. It is the UART ABI with the Pi
server and Laptop B test generator.

## Goal

The FPGA receives already-quantized 28 x 22-bit feature records from Pi over
UART, classifies them using the existing Decision Tree / BRAM model, then
returns a binary RESULT frame to Pi. The FPGA communicates with Pi purely over
a direct 2-wire hardware UART (TX/RX + GND) on GPIO header P6 without any USB
cable or USB-to-UART bridge. The FPGA must not receive, parse, forward, or
transmit Ethernet frames in this project.

## Hardware constraints

* Device: GW5A-LV25UG324C2/I1, device version B.
* 50 MHz clock: T9, LVCMOS33.
* Reset active-low: B16, LVCMOS15, pull-up.
* UART RX from Pi (GPIO14): C17 (Header P6 Pin 1 / GPIO0), LVCMOS33, pull-up.
* UART TX to Pi (GPIO15): G14 (Header P6 Pin 4 / GPIO3), LVCMOS33, pull-up, drive 8.
* UART uses 115200 8N1, one 50 MHz clock domain only; no generated/gated clock.
* UART RX has a two-flip-flop synchronizer and centre sampling.

## RTL requirements

Create separate readable Verilog-2001 modules for UART RX/TX, COBS frame RX,
CRC16, feature unpacker, feature FIFO, classifier adapter, result frame TX,
and `top_pi_uart_ids.v`.

The classifier adapter must reuse the verified Decision Tree/BRAM implementation
from `ip_final`, but bypass `ids_feature_quantizer`: its input is already 28 x
22-bit encoded data. Preserve the model BRAM update/activation capability or
provide a documented model preload image. Do not silently change model format.

Use a FIFO of at least four 616-bit feature records. Reject malformed frames
without changing FIFO state. Preserve and return the FEATURE sequence. Provide
sticky counters for malformed COBS, bad CRC, feature FIFO overflow, accepted
records, result frames, and classifier errors. Export only safe debug signals;
do not flood UART with ASCII logs.

## Mandatory verification

Create self-checking simulation that covers: valid feature frame, COBS byte
zero in payload, bad CRC, invalid length, back-to-back records, FIFO full,
sequence preservation, result decoding, reset, and a known golden feature
vector matching the existing Decision Tree result.

Run simulation, Gowin synthesis and P&R. Require setup violations = 0 and hold
violations = 0. Produce a pin report confirming T9/B16/C17/G14 and copy the final
bitstream to `release/pi_uart_ids.fs`. Add a README with programming and wiring
instructions (Pi GPIO14 -> C17, Pi GPIO15 <- G14, common GND). Do not claim
hardware PASS without a Pi hardware log.
