# Laptop B — IDS Raw Traffic Generator & Web Control Station

Generate deterministic raw Ethernet/IPv4/UDP test frames for the Pi server.
Provides both a CLI tool and a modern web dashboard for configuration,
simulation, inspection, and monitoring.

## Architecture

```text
┌──────────────────────────────────────────┐
│  Laptop B                                │
│  ┌────────────────────────────────────┐  │
│  │  Web Dashboard (http://localhost:5000) │
│  │  ┌──────────┐  ┌────────────────┐ │  │
│  │  │ Flask API │──│ send_raw_traffic│ │  │
│  │  └──────────┘  └────────────────┘ │  │
│  └────────────────────────────────────┘  │
│            │ Ethernet (Scapy raw)        │
└────────────┼─────────────────────────────┘
             ▼
┌──────────────────────────────────────────┐
│  Raspberry Pi (eth0, UDP port 40000)     │
│  ┌──────────┐   ┌───────────────────┐   │
│  │ Capture   │──▶│ Feature Extractor │   │
│  └──────────┘   └───────────────────┘   │
│        Dashboard: http://<pi-ip>:8080    │
│            │ UART                        │
│            ▼                             │
│  ┌──────────────────────────────────┐   │
│  │  FPGA IDS Classifier             │   │
│  └──────────────────────────────────┘   │
└──────────────────────────────────────────┘
```

## Prerequisites

1. **Windows 10/11** (tested)
2. **Python 3.9+** with pip
3. **Npcap** — download and install from [npcap.com](https://npcap.com/#download)
   * During installation, check **"Install Npcap in WinPcap API-compatible mode"**
4. **Administrator privileges** — required for raw Ethernet packet sending

## Quick Start

### 1. Install dependencies

```powershell
cd ME\fpga\pi_uart_ids\laptop_b_generator
pip install -r requirements.txt
```

### 2. Configure

Edit `config.json` with your Pi's MAC and IP address:

```json
{
    "interface": "Ethernet",
    "pi_mac": "dc:a6:32:xx:xx:xx",
    "pi_ip": "192.168.1.100",
    "dst_port": 40000,
    "packet_count": 10,
    "rate_pps": 5.0,
    "payload_size": 64,
    "start_sequence": 1,
    "web_server_port": 5000
}
```

### 3. Run the Web Dashboard

**Option A — Batch file (double-click):**
Right-click `run_web_ui.bat` → **Run as administrator**

**Option B — PowerShell:**
```powershell
# Run as Administrator
.\run_web_ui.ps1
```

**Option C — Direct:**
```powershell
python app.py
```

Open your browser to **http://127.0.0.1:5000**

### 4. CLI Mode (headless)

```powershell
# Send 20 packets at 10 pps
python send_raw_traffic.py --count 20 --rate 10

# Dry-run — inspect a packet without sending
python send_raw_traffic.py --dry-run

# Network diagnostics
python send_raw_traffic.py --verify-network
```

## Web Dashboard Features

| Feature | Description |
|---------|-------------|
| **Adapter & Target Config** | Select network adapter, set Pi MAC/IP, view source info |
| **Simulation Controls** | Sliders for packet count (1–1000), rate (0.5–50 pps), start sequence, payload size |
| **Send Traffic** | Live transmission with real-time progress bar and counter |
| **Stop** | Immediately cancels active sending |
| **Dry-Run / Inspect** | Decode protocol layers and formatted hex dump without sending |
| **Network Diagnostics** | ICMP ping, Npcap check, Admin privileges, Pi Dashboard probe |
| **Open Pi Dashboard** | One-click link to `http://<pi-ip>:8080` |
| **Live Packet Log** | Streaming table with timestamp, sequence, size, hex preview, status |
| **Health Badges** | Real-time indicators for Npcap, Admin, Pi reachability |

## Packet Format

Per `PROTOCOL_CONTRACT.md`, the UDP payload is:

```text
ASCII "IDSRAW1" (7 bytes) | sequence:u32-le | deterministic test bytes
```

Packets are addressed to the Pi's MAC and IPv4 address on UDP port **40000**.

## Troubleshooting

### "Permission denied" or "socket operation" errors
→ Run as **Administrator**. Right-click the `.bat` file or terminal → "Run as administrator".

### "Npcap not found"
→ Install Npcap from https://npcap.com/#download
→ Check "Install Npcap in WinPcap API-compatible mode" during setup.
→ Restart your terminal/Python after installing.

### Packets sent but Pi doesn't receive them
→ Verify the Pi's MAC address matches exactly (check with `ip link show eth0` on Pi).
→ Ensure Laptop B and Pi are on the same Layer 2 network (direct cable or same switch).
→ Check Windows Firewall isn't blocking outbound traffic.
→ Use **Dry-Run** to verify packet structure.

### "No route to host" / Ping fails
→ Verify IP addresses. Laptop B and Pi should be in the same subnet.
→ Try direct Ethernet cable between Laptop B and Pi.
→ Disable VPN if active.

## End-to-End Validation

> ⚠ **End-to-End PASS requires matching Pi dashboard / FPGA classification
> results at `http://<pi-ip>:8080`.**

Merely sending packets from Laptop B does NOT constitute a PASS. You must:

1. Send test traffic from this tool.
2. Open the Pi Dashboard at `http://<pi-ip>:8080`.
3. Verify that packets are received, features are extracted, and FPGA classification results are returned.
4. Compare sequence numbers and classification results.

## API Reference

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET`  | `/api/config` | Get current config + detected adapters |
| `POST` | `/api/config` | Update runtime configuration |
| `GET`  | `/api/interfaces` | List network adapters |
| `POST` | `/api/verify` | Run network diagnostics |
| `POST` | `/api/dry-run` | Build sample frame, return decoded info |
| `POST` | `/api/send` | Start packet transmission |
| `POST` | `/api/stop` | Stop active transmission |
| `GET`  | `/api/status` | Live transmission status + packet log |

## File Structure

```
laptop_b_generator/
├── config.json          # Runtime configuration
├── send_raw_traffic.py  # Core generator module (library + CLI)
├── app.py               # Flask web server + dashboard
├── requirements.txt     # Python dependencies
├── run_web_ui.bat       # Windows batch launcher (web)
├── run_web_ui.ps1       # PowerShell launcher (web)
├── run_generator.bat    # Windows batch launcher (CLI)
├── run_generator.ps1    # PowerShell launcher (CLI)
└── README.md            # This file
```
