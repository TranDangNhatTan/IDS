# Phase 7 — Tiền xử lý, feature ingest và tích hợp packet-to-tree

## Hai đường vào được hỗ trợ

### Đường release: raw feature record → tree

`ids_top.v` là đường khuyến nghị để tích hợp lần đầu:

```text
SW/MCU/feature collector
  → 28 raw fields, mỗi field 32 bit
  → ids_feature_ingest
  → ids_feature_quantizer
  → 616-bit integer snapshot
  → ids_tree_engine
```

Đường này đã kiểm tra toàn bộ 22.156 golden vectors end-to-end và giữ đúng contract train.

### Đường packet reference

`ids_packet_top.v` minh họa pipeline hoàn toàn trong RTL:

```text
Ethernet byte stream
  → ids_packet_parser
  → ids_flow_table
  → ids_history_window
  → ids_feature_ingest
  → ids_tree_engine
```

Đây là kiến trúc tham chiếu có thể mô phỏng. Packet top hiện dùng flow table 16 entry; trước khi dùng production cần thay lookup fully-associative bằng kiến trúc hashed/banked phù hợp BRAM và xác nhận semantics feature với nguồn traffic thực tế.

## Các module

| File | Chức năng |
|---|---|
| `ids_rate_quantizer.v` | Tính Q0.16 theo `round-to-nearest, ties-to-even`; báo chia zero. |
| `ids_feature_quantizer.v` | Scale, shift và saturation 28 feature theo schema. |
| `ids_feature_ingest.v` | Buffer ready/valid một record và chốt snapshot ổn định. |
| `ids_packet_parser.v` | Parser Ethernet-II, IPv4, TCP/UDP từ stream 8-bit. |
| `ids_history_window.v` | Reference engine tạo 19 feature time/host history từ 256 flow đã đóng. |
| `ids_flow_table.v` | Bảng 16 bidirectional flow, lookup hai chiều, counter, FIN/RST close và timeout sweep. |
| `ids_single_flow_builder.v` | Module tối giản một flow để học/debug; packet top release dùng `ids_flow_table`. |
| `ids_top.v` | Raw-feature record đến classification. |
| `ids_packet_top.v` | Packet parser đến classification. |

## Quantization trong RTL

- `src_bytes_code = min(raw_src_bytes >> 2, 240748)`.
- `dst_bytes_code = min(raw_dst_bytes >> 6, 3309)`.
- Rate input của `ids_feature_quantizer` đã ở dạng Q0.16; `ids_rate_quantizer` tạo code từ numerator/denominator khi cần.
- Mọi counter đều saturate; không wrap.
- Category code phải theo `fpga_category_codes.csv`; code 0 là unknown.

`ids_rate_quantizer` tái hiện rule Python `np.rint(rate × 65535)`, gồm cả trường hợp đúng nửa (`ties-to-even`).

## Parser contract

Parser hiện hỗ trợ:

- Ethernet-II không VLAN.
- IPv4 với IHL hợp lệ.
- TCP, UDP và ICMP protocol code.
- TCP/UDP source/destination port.
- IPv4 address, total length, frame length, TCP flags và timestamp.
- Mapping một số service port phổ biến; port khác map `other`.

Parser từ chối/báo lỗi cho non-IPv4, IPv4 fragment khác fragment đầu, IHL sai. VLAN và IPv6 chưa hỗ trợ.

## Cảnh báo semantic quan trọng

NSL-KDD chứa feature connection đã được dataset generator tính sẵn, không chứa PCAP để chứng minh packet extractor tương đương tuyệt đối. Đặc biệt:

- `service` không phải lúc nào cũng suy ra hoàn hảo từ destination port.
- `flag` của NSL-KDD là trạng thái connection, không đơn thuần là TCP flags của một packet.
- Time/host window phụ thuộc định nghĩa cửa sổ và thứ tự đóng flow.
- `ids_flow_table` reference có 16 entry fully-associative; khi đầy sẽ phát `flow_table_full`. Production nên thay lookup combinational bằng hashed/banked BRAM và hazard controller.

Vì vậy `ids_packet_top` là reference/demo kiến trúc. Artifact có parity chính thức với model là đường `ids_top` nhận 28 raw feature theo contract. Không được dùng kết quả packet demo để tuyên bố giữ nguyên accuracy NSL-KDD nếu chưa có PCAP/telemetry ground truth.

## Kết quả mô phỏng

```text
FEATURE_BLOCKS_PASS
IDS_TOP_PASS vectors=22156
PACKET_TOP_PASS class=18 leaf=1087
```

Test bao phủ Q0.16 rounding/divide-zero, history rate, parser TCP port 80, raw-feature quantization và packet-to-leaf traversal. Packet top xen kẽ flow A và flow B trước khi đóng flow A, xác nhận lookup/state nhiều entry không bị ghi đè.
