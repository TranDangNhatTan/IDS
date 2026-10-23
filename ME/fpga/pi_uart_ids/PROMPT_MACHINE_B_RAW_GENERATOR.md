# Prompt C — Laptop B raw Ethernet traffic generator & visual control webserver

You are a senior Windows networking, full-stack Python engineer. Implement the
Laptop B traffic generator and visual control web server in
`ME/fpga/pi_uart_ids/laptop_b_generator/`. Read `../PROTOCOL_CONTRACT.md` before
writing anything. Do not connect to FPGA UART, do not SSH into Pi, and do not
change the UART protocol or payload format.

## Goal

Generate deterministic raw Ethernet/IPv4/UDP test frames for the Pi server to
capture on `eth0`. Laptop B serves as both a scriptable traffic generator and
an interactive, visual web control station where the operator can configure,
simulate, inspect, and monitor raw packet transmissions in real time.

## Deliverables

1. `config.json`:
   * Adapter/interface name, Pi destination MAC, Pi destination IP, destination
     UDP port 40000, source IP/MAC (optional / auto-detected), default packet
     count, rate (pps), payload size, starting sequence, and web server port
     (e.g., 5000).
2. `send_raw_traffic.py`:
   * Core generator module using Python and Scapy. Builds and sends Ethernet ->
     IPv4 -> UDP packets addressed to the configured Pi MAC/IP/UDP port 40000.
   * Payload begins with exactly `IDSRAW1` (7 bytes ASCII), followed by a `u32`
     little-endian sequence, then deterministic test bytes. No UART code.
   * Supports programmatic use as a library (with background sending thread,
     cancel event, and progress callbacks) as well as standalone CLI execution
     with `--config`, `--count`, `--rate`, `--start-sequence`, `--dry-run`, and
     `--verify-network`.
3. `app.py` (Visual Web Server):
   * Lightweight Python web server (FastAPI or Flask) serving a modern, clean,
     responsive web dashboard accessible at `http://localhost:5000` (or
     `http://127.0.0.1:5000`).
   * REST API endpoints:
     * `GET /api/config`: get current configuration and detected network adapters.
     * `POST /api/config`: update runtime configuration.
     * `GET /api/interfaces`: list detected network adapters (Name, Description, MAC, IP).
     * `POST /api/verify`: run network diagnostics (Npcap check, Admin privileges,
       ping Pi IP, check Pi port 8080 dashboard) and return JSON results.
     * `POST /api/dry-run`: build a sample frame and return decoded packet layers,
       field breakdown, hex dump, and payload inspection without sending.
     * `POST /api/send`: trigger transmission with custom count, rate, start sequence.
     * `POST /api/stop`: abort an active transmission immediately.
     * `GET /api/status`: return live transmission status, progress (sent/total),
       packet log buffer, and error messages.
4. Web UI Dashboard (`templates/` / `static/` or single-page embedded HTML/CSS/JS):
   * **Adapter & Target Configuration Card**: select adapter from dropdown, set Pi MAC
     and IP, view source IP/MAC.
   * **Simulation Controls**: sliders/inputs for Packet Count (1..1000), Rate (0.5..50 pps),
     Start Sequence, and Payload Size.
   * **Action Buttons**:
     * **Send Traffic**: starts live transmission with progress bar and counter.
     * **Stop**: immediately cancels active sending.
     * **Dry-Run / Inspect Frame**: displays decoded protocol layers and formatted hexdump.
     * **Network Diagnostics**: runs ICMP ping and probes Pi Dashboard at `http://<pi-ip>:8080`.
     * **Open Pi Dashboard**: one-click button / link to `http://<pi-ip>:8080` for end-to-end verification.
   * **Live Packet Log**: streaming table/terminal showing timestamp, sequence number,
     packet size, hex preview, and status.
   * **System Health Indicators**: badges for Npcap Driver, Admin Privilege, Pi Reachability.
5. Launchers & Documentation:
   * `run_web_ui.bat` & `run_web_ui.ps1`: single-click launchers to start the web server.
   * `run_generator.bat` & `run_generator.ps1`: CLI launchers for headless runs.
   * `requirements.txt`: `scapy`, `flask` or `fastapi`, `uvicorn`, etc.
   * `README.md`: complete setup instructions, troubleshooting (Npcap, Windows firewall,
     Admin rights), and end-to-end validation guidelines.

## Operational & Safety Rules

* Must validate MAC format, IPv4 format, destination port (must strictly be 40000),
  and rate > 0 before sending.
* Clearly warn or alert when not running as Administrator or if Npcap driver is missing.
* Ensure thread safety during packet transmission so that stopping from the web UI
  is instantaneous and does not leave hanging background threads.
* Do not report end-to-end PASS merely because packets were transmitted from Laptop B.
  The UI and docs must explicitly state: "End-to-End PASS requires matching Pi dashboard /
  FPGA classification results at http://<pi-ip>:8080."
