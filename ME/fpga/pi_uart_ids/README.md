# Pi–FPGA IDS: one full-duplex UART

## Physical connection

| Raspberry Pi 4 | ACG525 / FPGA | Direction |
|---|---|---|
| GPIO14 / TXD0, physical pin 8 | P6-GPIO0 / C17 | Pi -> FPGA |
| GPIO15 / RXD0, physical pin 10 | P6-GPIO3 / G14 | FPGA -> Pi |
| GND, physical pin 6 | ACG525 GND | common reference |

This is one full-duplex UART link.  Open **one** Pi device, `/dev/serial0`, at
115200 baud, 8N1, no flow control. Never attach 5 V or RS-232 levels. The
on-board CH9102F and all V7/V8 pins are intentionally outside this project.

## FPGA operation

`uart_pi_rx` on C17 accepts the COBS FEATURE frames defined by
[`PROTOCOL_CONTRACT.md`](PROTOCOL_CONTRACT.md). `uart_pi_tx` on G14 sends COBS
RESULT frames. The feature FIFO has four 616-bit records. A malformed FEATURE
frame does not advance the FIFO.

The reused classifier model store needs a model loaded and activated before
traffic. The legacy `model_update_uart` maintenance loader shares the same C17
RX wire; use it only with FEATURE traffic stopped. This does not add a second
UART or modify FEATURE/RESULT framing. LED meaning: LED0 reset released, LED1
model loaded/activated, LED2 one or more accepted FEATURE records, LED3 sticky
input/model error.

Read [MODEL_LOADING.md](docs/MODEL_LOADING.md) before deployment: a feature
stream alone cannot initialize the runtime BRAM model after FPGA configuration.

## Build and verify

```powershell
cd ME/fpga/pi_uart_ids
iverilog -g2012 -DSIMULATION -s top_pi_uart_ids -o sim_compile.vvp src/uart_rx_sync.v src/uart_tx_sync.v src/feature_frame_rx.v src/result_frame_tx.v src/top_pi_uart_ids.v ../ip_final/src/model_update_uart.v ../ip_final/src/ids_tree_rom_banked.v ../ip_final/src/ids_tree_engine_live.v ../ip_final/src/deps/ids_node_decoder.v ../ip_final/src/deps/ids_feature_regfile.v
powershell -ExecutionPolicy Bypass -File .\scripts\build_gowin.ps1
```

The second command is the authority for synthesis, P&R, pin report, timing and
`release/pi_uart_ids.fs`. Hardware is PASS only after a Pi log verifies a
round-trip RESULT with the same sequence number.
