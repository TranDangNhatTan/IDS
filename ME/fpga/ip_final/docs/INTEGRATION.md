# IP-final integration contract

`ip_final` is the deployable ACG525 project. It owns the complete RTL file
set used by Gowin, the upload image, UART dashboard and host traffic scripts.
`src/deps` is a frozen local copy of the verified Ethernet bridge and feature
pipeline dependencies; neither `ip_final.gprj` nor `build_gowin.tcl` points to
RTL outside this directory.

## Runtime flow

1. Machine A sends Ethernet frames to LAN8720/RMII.
2. The verified bridge forwards frames to RTL8211F/RGMII and Machine B. It is
   the sole owner of all Ethernet TX pins.
3. A duplicated RMII deserializer passively observes the A-to-B stream.
4. Parser, flow table, history features and decision-tree engine generate a
   prediction. A classifier result is serialized to the laptop over UART.
5. The laptop dashboard displays predictions, rates and alerts. It sends the
   1,273-word tree image through the same UART after each FPGA configuration.

Ethernet forwarding is independent of the IDS and continues when model upload
or classification is disabled. Classification is deliberately gated until a
complete UART upload is activated.

## Resource profiles

`ids_packet_top_live` is the integrated functional profile used by the board
top and parity tests. It keeps the reference parallel history calculation so
that it preserves the established packet-feature contract.

`src/deps/ids_history_window_bram.v` is the resource profile implementation:
one packed 92-bit RAM, one read per clock, and a 513-cycle query at depth 256.
It has a dedicated regression in `tb/tb_ids_history_window_bram.v`.

It is intentionally not substituted silently into `ids_packet_top_live`: the
reference flow table consumes history in the close-event cycle, whereas a
single-port BRAM returns it hundreds of cycles later. A correct full-rate
replacement requires a close-event FIFO and a result-valid handshake. Until
that queued flow profile is added and compared against the software vectors,
the board build uses the verified functional profile rather than reporting a
resource optimization that changes or loses live records.

The live decision-tree model store *is* an inferred writable block RAM
(`ids_tree_rom_banked`), populated at runtime by UART. The small 16-entry
associative flow table remains registers by design: mapping roughly 3 Kbit to
a 16-Kbit block RAM wastes memory and removes its one-cycle lookup.

## Required verification before programming

```powershell
cd ME\fpga\ip_final
.\scripts\verify_ip_final.ps1
.\build_and_program.ps1
```

The verifier checks local-source elaboration, BRAM-history behavior and the
UART update protocol. After Gowin PNR completes, inspect its utilization
report: the authoritative proof of hardware RAM mapping is a nonzero BSRAM
count, not the `ram_style` attribute or a synthesis "Extracting RAM" message.
