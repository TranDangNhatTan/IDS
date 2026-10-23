# Prompt A — ACG525 FPGA IDS + volatile UART model loader

You are a senior Gowin FPGA engineer. Implement a new standalone project under
`ME/fpga/pi_uart_ids/fpga/`. Do not modify `ME/fpga/ip_final*` or
`ME/fpga/demo_connect_pi4`. Read `../PROTOCOL_CONTRACT.md` completely and
implement protocol v2 exactly.

## Required behavior

FPGA receives the model only from Pi UART after each FPGA boot, validates and
commits it into writable BRAM, then receives already-encoded FEATURE records,
runs the existing decision-tree model, and sends binary RESULT frames to Pi.
It never handles Ethernet. The active model must survive a failed subsequent
upload but is expected to disappear after FPGA configuration/reset.

## Fixed hardware

* GW5A-LV25UG324C2/I1, device version B.
* Clock: **50 MHz**, T9, LVCMOS33. Do not use 500 MHz unless the board receives
  a separately verified 500-MHz clock and constraints are changed deliberately.
* Reset: B16, active-low, LVCMOS15 with pull-up.
* UART RX: C17 / P6 GPIO0, LVCMOS33 pull-up; Pi GPIO14 pin 8 drives it.
* UART TX: G14 / P6 GPIO3, LVCMOS33 pull-up, drive 8; drives Pi GPIO15 pin 10.
* GND is common. UART is 115200 8N1, one 50-MHz synchronous domain, RX double
  synchronizer and centre sampling; no generated/gated clocks.

## RTL

Provide readable Verilog-2001 modules for UART RX/TX, COBS RX/TX, CRC16,
protocol dispatcher, model staging writer/bitmap/CRC32, dual-bank or otherwise
transactional model BRAM, classifier adapter, 4+ deep 616-bit feature FIFO,
RESULT encoder, and `top_pi_uart_ids.v`.

Reuse verified tree semantics/model word format from `ip_final`, but do not use
`ids_feature_quantizer`: 22-bit features are pre-encoded. Enforce v2 BEGIN,
WRITE, COMMIT, STATUS and ACK status codes exactly. ACK every valid request;
MODEL_WRITE duplicates must be idempotent. Do not accept FEATURE until a model
is committed. Preserve feature sequence in RESULT. Expose safe sticky counters
for malformed COBS/CRC, upload errors, accepted nodes, active model version,
feature FIFO overflow, accepted features, results, and classifier errors.

## Verification and delivery

Create self-checking simulation for COBS zero bytes, bad CRC/length/version,
model BEGIN/1,273 WRITE/COMMIT success, duplicate write, bad index, missing
node, bad image CRC, failed upload retaining old model, reset requiring upload,
back-to-back FEATURE, FIFO full, sequence preservation and golden inference.
Run synthesis/P&R with zero setup and hold violations. Deliver constraints,
pin/timing reports, README/programming instructions, tests, and
`release/pi_uart_ids.fs`. Do not claim hardware pass without a Pi capture log
showing MODEL_COMMIT_ACK and a matching FEATURE/RESULT pair.
