# Prompt B — Raspberry Pi server implementation

You are a senior Raspberry Pi 4/Linux networking and Python engineer. Create a
Pi server project under `ME/fpga/pi_uart_ids/pi_server/`. Read
`../PROTOCOL_CONTRACT.md` first and implement it exactly. Do not change the
protocol contract or FPGA RTL.

## Role

Pi is the server. It captures raw Ethernet test traffic on `eth0`, produces the
28 already-encoded 22-bit features required by the model, sends FEATURE frames
to FPGA, receives RESULT frames, and serves a dashboard to Laptop B.

## Required components

* `config.json`: eth interface, Pi data IP, dashboard port 8080, UART TX port
  `/dev/serial0`, explicit UART RX CH9102F device, baud, timeouts and retry
  limit. Do not hardcode these settings in Python.
* `protocol.py`: COBS, CRC-16/CCITT-FALSE, feature 22-bit pack/unpack, frame
  codec, strict validation and unit tests using the protocol contract vectors.
* `capture.py`: capture Ethernet/IPv4/UDP destination port 40000 on `eth0`;
  validate `IDSRAW1` and the little-endian source sequence. Support promiscuous
  mode only when configured. Handle malformed traffic without crashing.
* `features.py`: one documented canonical mapping of captured traffic into 28
  features. Apply the exact feature order, scale and saturation from
  `ip_final/src/deps/ids_feature_quantizer.v`; do not invent a second mapping.
* `uart_client.py`: opens `/dev/serial0` TX and the configured `/dev/ttyUSB*`
  RX independently at 115200 8N1/no flow control. One outstanding FEATURE
  transaction, timeout/retry twice, sequence matching and result deduplication.
* `app.py`: lightweight FastAPI or Flask dashboard/API. Show capture count,
  accepted UART records, retry/timeout/CRC errors, result count, last sequence,
  class, leaf, steps, error, and timestamps. Never claim accuracy without labels.
* `run_server.py`: single command launcher with clear startup diagnostics.

## Operational requirements

Use a Python virtual environment and PySerial. Document `raspi-config`: serial
login shell disabled, serial hardware enabled. Ensure the user has dialout
permission. Provide `systemd` service example but do not automatically install
or enable it. Log JSON Lines with rotation.

## Tests and handoff

Provide unit tests for the protocol and feature pack/unpack, plus a mock UART
test with known RESULT frames. Provide commands to find the CH9102F port with
`python3 -m serial.tools.list_ports`. The dashboard must bind to the configured
Pi network address so Laptop B can open `http://<pi-ip>:8080`.
