# Demo IDS qua LAN — ACG525

## Luồng dữ liệu

```text
Web dashboard trên Laptop
  ├─ MOD1: 1.273 node Decision Tree ──UDP 55002──> BRAM FPGA
  ├─ ACK1 <───────────────────────────UDP 55003── FPGA xác nhận model
  ├─ FTR2: seq + 28 feature uint32 ──UDP 55002──> Decision Tree core
  └─ IDS1: seq + class + leaf + steps <──UDP 55003── FPGA
```

Laptop chịu trách nhiệm tiền xử lý CSV/raw packet thành `label,f0,...,f27`.
FPGA chỉ nhận 28 feature đã chuẩn hóa, thực hiện quantize đúng như pipeline
train/export, suy luận Decision Tree và trả kết quả.

## Giao thức

| Payload | Hướng | Ý nghĩa |
|---|---|---|
| `MOD1 01` | Laptop → FPGA | Xóa trạng thái upload cũ |
| `MOD1 02 + addr_le16 + word_le64` | Laptop → FPGA | Ghi một node vào BRAM |
| `MOD1 03` | Laptop → FPGA | Commit model |
| `ACK1` | FPGA → Laptop | Số node nhận, version, counters |
| `FTR2 + seq_le32 + 28*u32_le` | Laptop → FPGA | Một vector kiểm thử |
| `IDS1` | FPGA → Laptop | Dự đoán và telemetry của vector |

`seq` được dashboard dùng để ghép prediction với label, do đó accuracy không
phụ thuộc thứ tự UDP reply.

## LEDs

| LED | Trạng thái |
|---|---|
| D0 | heartbeat: FPGA/clock/reset sống |
| D1 | PHY đã hết reset và PLL 25 MHz đã lock |
| D2 | RGMII IDDR đã tạo được byte Ethernet hợp lệ sau preamble/SFD |
| D3 | đã nhận UDP protocol hợp lệ hoặc đã phát reply |

## Cách demo

1. Nạp `release/ip_final_core.fs`; đợi D0 nhấp nháy.
2. Bảo đảm laptop và FPGA cùng switch, Ethernet Windows phải báo `Up` và
   **`100 Mbps`**. Bản bitstream này chạy RGMII 25 MHz/100BASE-TX.
3. Chạy server bằng `server/run_dashboard.ps1`, mở `http://127.0.0.1:8081`.
4. Target broadcast: `192.168.50.255`; UDP port: `55002`.
5. Upload model, để `Model packets/s = 200`. Chờ ACK1; D2 phải sáng ngay
   khi laptop gửi traffic, D3 sáng khi parser nhận MOD1 hợp lệ.
6. Chọn `demo_data/golden_10k_labeled.csv` rồi Upload CSV.
7. Bắt đầu ở `50 records/s`. Khi received = planned, pending=0 và drops=0,
   dashboard hiển thị accuracy và result rate. Tăng dần rate để đo thông lượng.

Accuracy trên dashboard chỉ có ý nghĩa sau khi có đủ IDS1 cho các dòng có label.
Nếu D1 không sáng: kiểm tra target/subnet/link. Nếu D1 sáng nhưng D3 tắt: kiểm
tra model ACK trước và ghi lại event log để debug parser/reply.
