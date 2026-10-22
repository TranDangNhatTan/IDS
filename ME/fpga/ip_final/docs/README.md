# IP Final: ACG525 inline IDS demo

Tài liệu tường thuật tiếng Việt đầy đủ (kiến trúc, model UART, kiểm chứng,
tài nguyên, build và demo) nằm ở `02_bao_cao_trien_khai_vi.md`.

This is a separate Gowin project for the physical demonstration.  It preserves
the verified RGMII↔RMII Ethernet bridge and adds a passive IDS monitor to the
Machine-A/RMII receive stream.  The monitor cannot stall Ethernet forwarding.

```text
Machine A (router/source) -- LAN8720/RMII -- ACG525 -- RTL8211F/RGMII -- Machine B (switch/receiver)
                                              |
                                              +-- UART TTL 115200 8-N-1 -- Laptop/server
```

## What is implemented

- Bidirectional L2 bridge comes from the passing `demo_connect` design.
- The duplicated RMII deserializer is a read-only tap into
  `ids_packet_parser → ids_flow_table → ids_history_window → Decision Tree`.
- The model BRAM starts empty after FPGA configuration. The server uploads the
  canonical `dt_fpga_flow28_fixed/node_rom.mem` through UART before packet
  classification is enabled.
- The tree uses one BRAM model image. Starting an update pauses packet
  classification; RAM writes and activation happen only after the current tree
  inference is idle. Ethernet forwarding continues throughout the update.
- UART telemetry emits one line for every completed inference:
  `IDS,<class hex>,<leaf hex>,<steps hex>,<error>,<bank>,<version hex>`.
- The dashboard parses those lines, records events, event rate and alert count.

The monitor currently covers the A→B direction (the RMII/LAN8720 ingress). The
return direction is bridged but not classified in this release. `ids_packet_top`
remains a packet-feature reference, not a claim of NSL-KDD feature equivalence
on arbitrary live packets.

## UART wiring

Use a 3.3-V TTL UART adapter, common ground, 115200 baud, 8-N-1.

```text
FPGA V8 (uart_tx) -> adapter RXD
adapter TXD        -> FPGA V7 (uart_rx)
FPGA GND           -> adapter GND
```

`V8` is the existing verified TX pin. V7 is an available 3.3-V input in the
current constraint report but must be checked against the actual board UART
connector/adapter before connecting it. Never connect RS-232 voltage levels.

## Model upload protocol

The model is a Decision Tree node image, not a neural-network weight matrix.
Start an image with `A5 5A 12 12`. Each write command is:

```text
A5 5A 10 address_lo address_hi word_byte_0 ... word_byte_7 XOR_checksum
```

`word_byte_0` is node bits `[7:0]`; the checksum is XOR of command and payload.
After exactly the intended 1,273 words have been sent, send `A5 5A 11 11` to
request activation. The FPGA rejects activation before all 1,273 words arrive
and discards frames with a bad checksum. The laptop web server verifies the
local image length before sending.

For a production system, add an authenticated signed manifest, a full-image
SHA-256 verified by a trusted controller, an ACK/NACK retry layer, and a model
compatibility/profile hash. Those are not implemented in this FPGA-only demo.

## Build and program

From PowerShell:

```powershell
cd ME\fpga\ip_final
.\scripts\verify_ip_final.ps1
.\build_and_program.ps1
```

The command generates `release/ip_final.fs`. Program that file to SRAM using
Gowin Programmer; only select external flash if you explicitly want persistent
boot configuration. Confirm both Ethernet links at 100 Mb/s and UART idle-high
before sending traffic.

## Run the physical demo

On Machine B first:

```powershell
.\ME\fpga\ip_final\scripts\run_machine_b.ps1 -Expected 100
```

On the laptop connected to UART:

```powershell
python .\ME\fpga\ip_final\server\ids_web_server.py --port COM17
```

Open `http://127.0.0.1:8080`. Then on Machine A:

```powershell
.\ME\fpga\ip_final\scripts\run_machine_a.ps1 -Count 100 -RateMbps 1
```

The dashboard's **Upload node_rom.mem** button is mandatory after every FPGA
configuration: it loads the BRAM model image and requests activation. Ethernet
forwarding continues, but classification remains disabled until this succeeds.
Do not send live traffic during the first hardware model-update test; first
verify the UART connection with FPGA telemetry.

## Evidence and limits

## Memory/resource architecture

`ids_history_window.v` is retained as the functional reference: its 256-entry
parallel scan is appropriate for simulation but cannot map to one BRAM read
port. `ids_history_window_bram.v` is the hardware implementation: entries are
packed into a single inferred RAM and scanned one per clock. A history query
takes `2 × HISTORY_DEPTH + 1` clocks (513 cycles at depth 256), saving LUT/FF
resources at the cost of latency. The 16-entry bidirectional flow table stays
as registers because its one-cycle associative lookup is smaller and faster
than spending a whole 16-Kbit BSRAM for roughly 3 Kbit of state.

Run the resource-focused regressions:

```powershell
.\ME\fpga\ip_final\tb\run_resource_tb.ps1
```

Expected tokens are `HISTORY_BRAM_PASS` and `MODEL_UPDATE_UART_PASS`.

`dt_fpga_flow28_fixed` achieved 95.4775% on its labeled held-out dataset.
The existing RTL parity test passes all 22,156 golden vectors. The live demo
does not automatically have ground-truth labels, therefore its web dashboard
must report predictions and performance only—not a fabricated live accuracy.
Measure live accuracy only with labeled replay traffic or by comparing recorded
feature records to a software reference.
