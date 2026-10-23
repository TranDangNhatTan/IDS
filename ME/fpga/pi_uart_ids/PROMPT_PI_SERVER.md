# Prompt B — Raspberry Pi server implementation

You are a senior Raspberry Pi 4/Linux networking and Python engineer. Create a
Pi server project under `ME/fpga/pi_uart_ids/pi_server/`. Read
`../PROTOCOL_CONTRACT.md` first and implement it exactly. Do not change the
protocol contract or FPGA RTL.

## Role

Pi is the server. It captures raw Ethernet test traffic on `eth0`, produces the
28 already-encoded 22-bit features required by the model, sends FEATURE frames
to FPGA over direct GPIO UART (`/dev/serial0`), receives RESULT frames back on
the same UART, and serves a dashboard to Laptop B at port 8080.

## Required components

* `config.json`: eth interface, Pi data IP, dashboard port 8080, single UART
  port `/dev/serial0` (used for both TX on GPIO14 and RX on GPIO15), baud 115200,
  timeouts and retry limit. Do not hardcode these settings in Python.
* `protocol.py`: COBS, CRC-16/CCITT-FALSE, feature 22-bit pack/unpack, frame
  codec, strict validation and unit tests using the protocol contract vectors.
* `capture.py`: capture Ethernet/IPv4/UDP destination port 40000 on `eth0`;
  validate `IDSRAW1` and the little-endian source sequence. Support promiscuous
  mode only when configured. Handle malformed traffic without crashing.
* `features.py`: one documented canonical mapping of captured traffic into 28
  features. Apply the exact feature order, scale and saturation from
  `ip_final/src/deps/ids_feature_quantizer.v`; do not invent a second mapping.
* `uart_client.py`: opens single full-duplex UART port `/dev/serial0` at 115200
  8N1 / no flow control. One outstanding FEATURE transaction, timeout/retry twice,
  sequence matching and result deduplication. Pure GPIO connection; no USB cable
  or USB-to-UART bridge is used.
* `app.py`: lightweight FastAPI or Flask dashboard/API. Show capture count,
  accepted UART records, retry/timeout/CRC errors, result count, last sequence,
  class, leaf, steps, error, and timestamps. Never claim accuracy without labels.
* `run_server.py`: single command launcher with clear startup diagnostics.

## Operational requirements

Use a Python virtual environment and PySerial. Document `raspi-config`: serial
login shell disabled, serial hardware enabled. Ensure the user has dialout
permission. Provide `systemd` service example but do not automatically install
or enable it. Log JSON Lines with rotation.

## Wiring and hardware settings

* Pi GPIO 14 (Physical Pin 8, TXD0) -> FPGA ACG525 Header P6 Pin 1 (C17, RX).
* Pi GPIO 15 (Physical Pin 10, RXD0) <- FPGA ACG525 Header P6 Pin 4 (G14, TX).
* Pi GND (Physical Pin 6) -> FPGA ACG525 Header P6 Pin GND (Common Ground).
* 3.3-V TTL levels only. No USB cable between Pi and FPGA is required.

## Tests and handoff

Provide unit tests for the protocol and feature pack/unpack, plus a mock UART
test with known RESULT frames. The dashboard must bind to the configured Pi
network address so Laptop B can open `http://<pi-ip>:8080`.
