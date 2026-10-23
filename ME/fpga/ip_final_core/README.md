# ACG525 FPGA IDS — LAN-only implementation

The application data path uses only the **onboard RTL8211F RGMII Ethernet
PHY**. The FPGA receives a Decision Tree model and preprocessed features over
UDP, then returns classification telemetry over UDP. UART is retained only as
a change-driven hardware diagnostic; it is not part of the IDS protocol.

## Artifacts

- Program this bitstream: `release/ip_final_core.fs`
- Verify RTL: `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify_ip_final_core.ps1`
- Check post-route timing: `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\check_timing.ps1`
- Build with mandatory timing gate: `powershell -NoProfile -ExecutionPolicy Bypass -File .\build_and_program.ps1`
- Start dashboard: `powershell -NoProfile -ExecutionPolicy Bypass -File .\server\run_dashboard.ps1`
- Dashboard: `http://127.0.0.1:8081`

The dashboard binds UDP port **55003** for replies. The FPGA receives model and
feature packets on UDP port **55002**. On this setup the Ethernet adapter is
`192.168.50.22/24`, so enter broadcast **`192.168.50.255`** in the dashboard.
The reply source IP is `192.168.50.50`.

## Wire protocol

The FPGA learns the source MAC, IPv4 address and UDP source port from each
incoming packet and sends the result back to that same laptop socket. No ARP or
static laptop MAC address is required in the demonstration network.

| Direction | UDP payload | Meaning |
|---|---|---|
| Laptop → FPGA | `FTR2 + seq_le32 + 28*uint32_le` | One feature record |
| FPGA → laptop | `IDS1 + seq_le32 + class + leaf_be16 + steps + error + version_be16 + accepted_be32 + dropped_be32` | Classification and FPGA counters |
| Laptop → FPGA | `MOD1 + 01` | Begin a model transfer |
| Laptop → FPGA | `MOD1 + 02 + address_le16 + node_le64` | Write one of 1,273 tree nodes |
| Laptop → FPGA | `MOD1 + 03` | Commit model |
| FPGA → laptop | `ACK1 + ready + words_be16 + version_be16 + accepted_be32 + dropped_be32` | Model activation acknowledgement |

The `seq` field makes accuracy correct even if UDP replies are lost or arrive in
a different order. The server tracks labels by sequence ID, never by result
arrival order.

## Demo procedure

1. Flash `release/ip_final_core.fs`.
2. Connect the FPGA Ethernet port and laptop to the same switch. Use the same
   IPv4 subnet for the laptop and the chosen broadcast target. This stable
   RGMII build requires Windows Ethernet status **Up / 100 Mbps**.
3. Run the PowerShell script and open the dashboard.
4. Click **Upload model**. Wait for the `model_ack` event and “FPGA ACK
   received: model active.” Do not start testing before this acknowledgement.
5. Upload a prepared CSV with `label,f0,...,f27`.
6. Start at **50 records/s** for first hardware verification. The page reports
   sent/result count, accuracy, offered input rate, completed result rate and
   FPGA accepted/dropped counters. Increase rate only when
   `pending=0`, `unmatched=0` and `FPGA drops=0`.

## LEDs

| LED | Signal |
|---|---|
| LED0 | 1 Hz heartbeat: FPGA configuration, clock and reset are alive |
| LED1 | PHY reset released and 25 MHz PLL locked |
| LED2 | Raw RGMII receive activity seen from PHY |
| LED3 | Valid MOD1/FTR2 protocol accepted or a reply emitted |

The verification script checks DDR RX/TX, IPv4/UDP filtering, Ethernet FCS,
MOD1 address de-duplication, all 1,273 BRAM words, repeated COMMIT, FTR2 and
the change-driven UART formatter.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\verify_ip_final_core.ps1
```
