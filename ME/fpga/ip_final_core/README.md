# ACG525 FPGA IDS — LAN-only implementation

This revision removes UART completely.  The laptop, switch/router and FPGA use
only Ethernet/RMII.  The FPGA receives a Decision Tree model and preprocessed
features over UDP, then returns classification telemetry over UDP.

## Artifacts

- Program this bitstream: `release/ip_final_core.fs`
- Start dashboard: `powershell -ExecutionPolicy Bypass -File .\server\run_dashboard.ps1`
- Dashboard: `http://127.0.0.1:8081`

The dashboard binds UDP port **55003** for replies. The FPGA receives model and
feature packets on UDP port **55002**. The default target is broadcast
`255.255.255.255`; use the FPGA/switch network broadcast address if Windows
does not route the global broadcast through the selected Ethernet adapter.

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
   IPv4 subnet for the laptop and the chosen broadcast target.
3. Run the PowerShell script and open the dashboard.
4. Click **Upload model**. Wait for the `model_ack` event and “FPGA ACK
   received: model active.” Do not start testing before this acknowledgement.
5. Upload a prepared CSV with `label,f0,...,f27`.
6. Start at **10,000 records/s**. The page reports sent/result count, accuracy,
   input rate and the FPGA accepted/dropped counters. Increase rate only when
   `pending=0`, `unmatched=0` and `FPGA drops=0`.

## LEDs

| LED | Signal |
|---|---|
| LED0 | 1 Hz heartbeat: FPGA configuration, clock and reset are alive |
| LED1 | Toggles when FPGA accepts an `FTR2` feature record |
| LED2 | Solid on when all 1,273 model words are committed and active |
| LED3 | Toggles when FPGA transmits an `IDS1` result or `ACK1` reply |

The testbench commands are:

```powershell
iverilog -g2012 -o tb\tb_lan_protocol.vvp tb\tb_lan_protocol.v src\ids_udp_feature_rx.v
vvp tb\tb_lan_protocol.vvp
iverilog -g2012 -o tb\tb_udp_reply_tx.vvp tb\tb_udp_reply_tx.v src\ids_udp_reply_tx.v src\deps\rmii_serializer.v
vvp tb\tb_udp_reply_tx.vvp
```
