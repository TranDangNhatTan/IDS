# Prompt C — Laptop B raw Ethernet traffic generator

You are a Windows networking/Python test engineer. Create the Laptop B traffic
generator in `ME/fpga/pi_uart_ids/laptop_b_generator/`. Read
`../PROTOCOL_CONTRACT.md` before writing anything. Do not connect to FPGA UART,
do not SSH into Pi, and do not change the UART protocol.

## Goal

Generate deterministic raw Ethernet/IPv4/UDP test frames for the Pi server to
capture. Laptop B is only a traffic generator and dashboard browser.

## Deliverables

* `config.json`: adapter/interface name, Pi destination MAC, Pi destination IP,
  destination UDP port 40000, source IP/MAC (optional), packet count, rate,
  payload size and starting sequence.
* `send_raw_traffic.py`: Python/Scapy tool that sends Ethernet -> IPv4 -> UDP
  packets addressed to the configured Pi MAC/IP/UDP port. Payload begins with
  exactly `IDSRAW1` followed by a u32 little-endian sequence, then deterministic
  test bytes. No UART code.
* `requirements.txt`, `README.md`, and a PowerShell launcher.

## CLI and checks

Support `--config`, `--count`, `--rate`, `--start-sequence`, `--dry-run`, and
`--verify-network`. Print the actual interface, source/destination MAC and IP,
UDP port, payload bytes and every sent sequence. Validate MAC/IP/port/rate
before sending. Clearly report missing Npcap, missing administrator privilege,
wrong adapter and send error.

`--dry-run` must build and print one complete frame without transmitting. The
default test sequence is 10 packets at 5 packets/s. The README must state that
Pi eth0 must be reachable by direct Ethernet cable or the same switch, and that
the laptop can view the Pi dashboard at `http://<pi-ip>:8080`.

Do not report end-to-end PASS merely because packets were sent. End-to-end PASS
requires a matching Pi dashboard/API result with the same sequence.
