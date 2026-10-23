# Pi–FPGA IDS protocol contract v2

This document is the UART ABI for the FPGA, Pi server, and Laptop B test
generator. Version 2 adds model upload. All three implementations must use it
unchanged.

## Topology and serial link

```text
Laptop B Ethernet -> Pi eth0
Pi pin 8 GPIO14/TXD0  -> ACG525 P6 GPIO0 -> FPGA C17 (UART RX)
Pi pin 10 GPIO15/RXD0 <- ACG525 P6 GPIO3 <- FPGA G14 (UART TX)
Pi pin 6 GND          -> ACG525 GND
Laptop B browser      -> http://192.168.10.2:8080
```

The link is direct 3.3-V TTL only: no 5-V, RS-232, USB cable, or USB UART.
It is 115200 baud, 8N1, no flow control, on one full-duplex Pi device
`/dev/serial0`. The ACG525 board clock is the verified **50 MHz** oscillator
on T9; do not assume 500 MHz.

## Common frame format

Every frame is COBS encoded and followed by one `0x00` delimiter. Decode it
before validating:

```text
version:u8 | type:u8 | sequence:u16-le | payload_length:u16-le | payload | crc16:u16-le
```

`version = 0x02`. CRC is CRC-16/CCITT-FALSE (polynomial `0x1021`, initial
`0xFFFF`, final XOR `0x0000`) over every decoded byte except the CRC itself.
Reject COBS, version, type, exact length, and CRC failures. Multi-byte fields
are little-endian. `sequence` is the request sequence and is copied to its ACK
or RESULT. The sender retries a request with the same sequence at most twice.

## Model upload — Pi to FPGA at every FPGA boot

The fixed model is `ME/hw/model_export/dt_fpga_flow28_fixed/node_rom.hex`:
exactly 1,273 lines, each a 16-hex-digit 64-bit node word. Pi owns the file and
retains it locally. FPGA model RAM is volatile: after each FPGA configuration,
Pi must upload and commit the complete image before sending FEATURE frames.

`image_crc32` is the standard IEEE CRC-32 of the concatenated binary node
words in file order, where each 16-digit hex word is converted to 8 bytes
little-endian. It is not a CRC of ASCII text.

| Direction | Type | Name | Exact payload |
|---|---:|---|---|
| Pi → FPGA | `0x01` | MODEL_BEGIN | `node_count:u16=1273 | image_crc32:u32 | requested_model_version:u16` (8 bytes) |
| FPGA → Pi | `0x81` | MODEL_BEGIN_ACK | `status:u8 | accepted_count:u16 | active_model_version:u16` (5 bytes) |
| Pi → FPGA | `0x02` | MODEL_WRITE | `node_index:u16 | node_word:u64-le` (10 bytes) |
| FPGA → Pi | `0x82` | MODEL_WRITE_ACK | `status:u8 | node_index:u16 | accepted_count:u16` (5 bytes) |
| Pi → FPGA | `0x03` | MODEL_COMMIT | `image_crc32:u32 | requested_model_version:u16` (6 bytes) |
| FPGA → Pi | `0x83` | MODEL_COMMIT_ACK | `status:u8 | accepted_count:u16 | active_model_version:u16` (5 bytes) |
| Pi → FPGA | `0x04` | MODEL_STATUS | empty (0 bytes) |
| FPGA → Pi | `0x84` | MODEL_STATUS_REPLY | `status:u8 | accepted_count:u16 | active_model_version:u16` (5 bytes) |
| FPGA → Pi | `0x90` | TRACE | `rx_bytes:u32 | valid_frames:u32 | upload_errors:u32 | accepted_nodes:u16 | error_flags:u8 | last_frame_type:u8` (16 bytes) |

Status: `0=OK`, `1=BAD_STATE`, `2=BAD_INDEX`, `3=BAD_COUNT`, `4=IMAGE_CRC`,
`5=BUSY`, `6=UNSUPPORTED_VERSION`. The FPGA clears the staging-valid bitmap on
accepted BEGIN. It ACKs duplicate MODEL_WRITE for an already received matching
index idempotently. COMMIT succeeds only when all 1,273 nodes were received and
the staging CRC matches. A failed upload must leave the prior active model
unchanged. FPGA must not accept FEATURE while upload/commit is incomplete.

Pi performs stop-and-wait for BEGIN, every WRITE, and COMMIT, shows confirmed
node count/progress in the dashboard, and retries a request at most twice.

For hardware diagnosis, FPGA also emits an unsolicited TRACE frame roughly
every 100 ms. `error_flags` bit 0..5 are respectively bad COBS, CRC, length,
version, UART framing, FIFO overflow. Pi logs/displays it but never treats it
as an ACK. TRACE proves FPGA TX works even when an inbound request is malformed.

## Inference

| Direction | Type | Name | Exact payload |
|---|---:|---|---|
| Pi → FPGA | `0x10` | FEATURE | 28 packed unsigned 22-bit values (77 bytes) |
| FPGA → Pi | `0x20` | RESULT | `class_id:u8 | leaf_node:u16 | step_count:u8 | error_code:u8 | model_version:u16` (7 bytes) |

For FEATURE, let `S` be a 616-bit little-endian stream:
`S[22*j +: 22] = feature[j]`, `payload[k] = S[8*k +:8]`. Values must be
`0..4194303`. Pi applies the exact order/caps from
`ME/fpga/ip_final/src/deps/ids_feature_quantizer.v`: specifically feature 4 is
raw source bytes `>>2`, capped 240748; feature 5 is raw destination bytes
`>>6`, capped 3309. FPGA must not quantize again. One FEATURE is outstanding at
once; duplicate RESULTS are deduplicated by sequence.

## Laptop B test traffic

Laptop B sends Ethernet/IPv4/UDP to Pi eth0, destination UDP port 40000:

```text
ASCII "IDSRAW1" (7 bytes) | sequence:u32-le | deterministic test bytes
```

Laptop B never accesses the FPGA UART. It may send labelled test profiles; Pi
may display prediction-versus-supplied-label test statistics, never live
accuracy for unlabelled traffic.
