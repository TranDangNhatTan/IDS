# Prompt B — Raspberry Pi server, model owner, and operations dashboard

You are a senior Raspberry Pi 4/Linux networking and Python engineer. Implement
under `ME/fpga/pi_uart_ids/pi_server/`. Read `../PROTOCOL_CONTRACT.md`
completely and implement protocol v2 exactly. Do not invent a second wire
protocol.

## Role

Pi is the only server. Laptop B injects test traffic through Ethernet; Pi
captures it on eth0, creates 28 already-encoded features, sends them to FPGA,
receives RESULT, and serves the dashboard at port 8080. Pi permanently stores
the fixed model file `ME/hw/model_export/dt_fpga_flow28_fixed/node_rom.hex`.
After every FPGA boot, operator-triggered or automatic model upload sends the
whole 1,273-node image through `/dev/serial0` and must finish successfully
before inference is enabled.

## Network and UART

* Default isolated test LAN: Pi `eth0` `192.168.10.2/24`; Laptop B Ethernet
  `192.168.10.1/24`; dashboard `http://192.168.10.2:8080`.
* Single direct TTL UART: `/dev/serial0`, GPIO14 TX pin 8 → FPGA C17/P6 GPIO0;
  FPGA G14/P6 GPIO3 → Pi GPIO15 RX pin 10; pin 6/common GND; 3.3 V only.
* UART is 115200 8N1/no flow control. Serial login shell must be disabled and
  hardware UART enabled in `raspi-config`. Document `dialout` and `CAP_NET_RAW`.

## Required components

* `config.json`: interface, Pi IP, port, UART configuration, timeouts/retries,
  model path/version, expected node count 1273, and log rotation settings.
* `protocol.py`: v2 COBS, CRC16, CRC32 image calculation, strict frame codec,
  feature pack/unpack, model payload codecs and contract-vector tests.
* `model_loader.py`: parse only 1,273 valid 16-hex-digit `node_rom.hex` words;
  convert each word to little-endian u64, calculate image CRC32, stop-and-wait
  BEGIN/WRITE/COMMIT with sequence matching/retry twice, STATUS recovery and
  progress callbacks. Never mark model active without COMMIT_ACK status OK.
* `capture.py`: safely capture Ethernet/IPv4/UDP port 40000 on eth0, validate
  `IDSRAW1 | sequence:u32-le`, handle malformed frames without crashing.
* `features.py`: one documented mapping only; exact RTL order/scaling/caps.
* `uart_client.py`: serialize model loading and FEATURE requests on the same
  full-duplex UART. No FEATURE during upload; one outstanding transaction.
* `app.py`: professional realtime dashboard/API with capture/UART link state,
  rates/bytes, CRC/retry/timeout errors, model version/status/progress, latest
  RESULT and event log. Add a dashboard action to upload a `.hex` file to Pi,
  validate it, retain it locally, and then start model load. Do not claim model
  active until FPGA COMMIT_ACK. No login is required on this isolated test LAN.
* `run_server.py`: diagnostics for IP binding, raw-capture permission, serial
  port, FPGA model status and clear startup guidance.

## Traffic/results

Laptop B source is `IDSRAW1` UDP port 40000 only. Support optional test labels
carried/configured by Laptop B and show prediction-versus-label metrics only
for that explicitly labelled test run; never claim accuracy for live unlabelled
traffic. When FPGA is offline or its model is inactive, retain safe dashboard
errors and stop FEATURE transmission instead of building an unbounded queue.

## Handoff

Use the existing venv `/home/vdas/Desktop/projects/pjs-env`, PySerial, JSONL
rotated logs, tests for protocol/model parser/mock UART and Flask API, plus a
systemd example (do not install it). Provide run/upload/recovery instructions.