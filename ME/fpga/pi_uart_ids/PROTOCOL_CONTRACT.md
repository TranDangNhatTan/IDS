# Pi–FPGA IDS protocol contract v1

This is the single source of truth for all three implementations. Do not change
any field, byte order, feature order, or CRC rule without updating every side.

## Physical topology

```text
Laptop B Ethernet NIC -> Pi eth0 (direct cable or same LAN)
Pi GPIO14/TXD0, physical pin 8 -> ACG525 P6-GPIO0 -> FPGA C17
Pi GND, physical pin 6 -> ACG525 GND
FPGA V8 -> onboard CH9102F -> USB cable -> Pi USB host (/dev/ttyUSB*)
Laptop B browser -> http://<pi-ip>:8080
```

Pi-to-FPGA and FPGA-to-Pi are independent UART directions. Laptop B is not
connected to the CH9102F during normal operation.

## UART electrical and serial settings

* 3.3-V TTL only; never connect RS-232 or 5 V.
* 115200 baud, 8 data bits, no parity, one stop bit, no flow control.
* Pi TX port: `/dev/serial0` (GPIO14/TXD0).
* Pi RX port: explicit `/dev/ttyUSB*` CH9102F device. Never read results from
  `/dev/serial0`.

## Framing

Each UART frame is COBS encoded and terminated by one `0x00` byte. CRC is
calculated before COBS encoding. A decoded frame is:

```text
version:u8 | type:u8 | sequence:u16-le | payload_length:u16-le | payload | crc16:u16-le
```

* `version = 0x01`
* CRC = CRC-16/CCITT-FALSE: polynomial `0x1021`, initial `0xFFFF`, no final
  XOR; cover all bytes from `version` through the final payload byte.
* Reject a frame on COBS, length, version, type, or CRC failure.
* Feature type is `0x10`; result type is `0x20`.

## FEATURE payload, Pi -> FPGA

Payload length is exactly 77 bytes. It contains 28 unsigned 22-bit encoded
features, indexed 0 through 27. Let `S` be a 616-bit little-endian bit stream:

```text
S[22*j +: 22] = feature[j], for j = 0..27
payload[k] = S[8*k +: 8], for k = 0..76
```

All feature values must be in `[0, 4194303]`. Feature semantics must match the
existing `ME/fpga/ip_final/src/deps/ids_feature_quantizer.v` exactly. In
particular, Pi produces the already-encoded values: feature 4 is raw source
bytes shifted right by 2 and capped at 240748; feature 5 is raw destination
bytes shifted right by 6 and capped at 3309. The remaining caps/order are the
ones in that RTL file. Do not quantize again inside the FPGA classifier.

Pi starts with at most one unacknowledged FEATURE frame. It retries the same
sequence at most twice after a configurable timeout. Pi deduplicates repeated
RESULT frames by sequence.

## RESULT payload, FPGA -> Pi

Payload length is exactly 7 bytes:

```text
class_id:u8 | leaf_node:u16-le | step_count:u8 | error_code:u8 | model_version:u16-le
```

The header `sequence` is copied from the corresponding FEATURE. A result is
emitted for each accepted feature record, including an inference error.

## Laptop B raw Ethernet test traffic

Laptop B generates Ethernet/IPv4/UDP frames addressed to Pi's MAC and IPv4
address, destination UDP port 40000. UDP payload is:

```text
ASCII "IDSRAW1" (7 bytes) | sequence:u32-le | test bytes
```

Pi captures this traffic on `eth0`, validates the marker and sequence, creates
the 28 encoded features, and publishes the complete lifecycle to its dashboard.
The traffic generator is only a test source; it never talks to the FPGA UART.
