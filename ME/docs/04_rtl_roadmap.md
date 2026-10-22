# 04 — Kiến trúc RTL và trạng thái triển khai

## Trạng thái hiện tại

| Thành phần | Trạng thái |
|---|---|
| Fixed-point node CSV | PASS |
| `.mem/.hex/.mif/.coe` | PASS |
| Node pack/unpack 64-bit | PASS |
| Verilog tree ROM/decoder/register/FSM | PASS simulation |
| Feature quantizer/ready-valid ingest | PASS simulation |
| Ethernet/IPv4/TCP parser reference | PASS simulation |
| 16-entry flow table/history reference | PASS simulation |
| Golden-vector testbench | PASS, toàn bộ 22.156 test vectors |
| Packet-to-tree testbench | PASS |
| Synthesis/place-and-route | NOT RUN theo yêu cầu |

## Kiến trúc

```text
Raw feature record ───────────────┐
                                 ├→ quantizer → snapshot → tree ROM/FSM → class_id
Packet stream → parser → flow/history ┘
```

Đường raw feature record là release path có parity với model. Đường packet là reference path để kiểm tra control/data integration.

## ROM/FSM

ROM 64-bit × 1.273 word, root node 0. Synchronous ROM dùng hai state cho mỗi decision:

```text
IDLE → WAIT_ROM → EVALUATE → WAIT_ROM → ... → LEAF
```

Model sâu tối đa 20; engine đặt guard 64 bước.

## Verification chain

```text
sklearn
  = Python integer/HDF5/CSV/ROM trên 147.674 rows
  = Verilog tree engine trên 22.156 golden vectors
  = Verilog raw-feature top trên 22.156 golden vectors
```

Packet reference test xen kẽ hai flow trong ba Ethernet/IPv4/TCP frame, sau đó đóng flow A bằng FIN và đi đến class 18, leaf 1087 như Python integer evaluator.

## Việc tiếp theo ngoài phạm vi hiện tại

- Multi-entry flow table và hazard control.
- CDC/FIFO với MAC clock.
- Mapping service/flag được hiệu chuẩn bằng PCAP/telemetry thật.
- Synthesis, resource report, timing closure và board bring-up.

Chi tiết xem tài liệu 06, 07 và 08.
