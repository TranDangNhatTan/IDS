# UART debug bridge Ethernet trên ACG525

## 1. Source và cấu hình

- `src/uart_tx_byte.v`: UART transmitter từng byte.
- `src/uart_debug_reporter.v`: gửi status word định kỳ.
- `src/top_acg525_rgmii_rmii_bridge.v`: thu thập cờ sticky từ ba clock domain.
- `tools/read_uart_debug.ps1`: đọc COM và giải mã status.
- FPGA UART TX: `V8`, `LVCMOS33`.
- Baud: `115200`, format `8-N-1`, flow control `None`.
- Chuỗi phát mỗi giây: `DBG=hhhh`.

Cờ sticky giữ mức 1 cho tới khi reset FPGA, nên không bỏ lỡ frame ngắn.

## 2. Đấu dây UART

Nếu dùng cổng/cáp UART của board thì chọn đúng COM được Windows nhận diện. Nếu
dùng USB-UART TTL ngoài:

```text
ACG525 UART_TX/V8  -> RXD của USB-UART
ACG525 GND         -> GND của USB-UART
```

Không nối TX với TX. Không cần nối VCC. Chỉ dùng UART TTL 3.3 V; không nối
trực tiếp cổng RS-232 có điện áp âm/dương cao.

## 3. Bảng bit `DBG=hhhh`

| Bit | Mask | Ý nghĩa |
|---:|---:|---|
| 0 | `0001` | onboard PHY đã thoát reset |
| 1 | `0002` | FSM đã phát xong chuỗi MDIO write |
| 2 | `0004` | FPGA quan sát được REF_CLK LAN8720 |
| 3 | `0008` | LAN8720 đã assert CRS_DV |
| 4 | `0010` | RMII RX đã giải mã được byte |
| 5 | `0020` | RMII RX đã nhận trọn frame |
| 6 | `0040` | RGMII TX phía RTL8211F đã hoạt động |
| 7 | `0080` | RTL8211F đã assert RGMII RX_CTL |
| 8 | `0100` | RGMII RX đã giải mã được byte |
| 9 | `0200` | RGMII RX đã nhận trọn frame |
| 10 | `0400` | RMII TX_EN phía LAN8720 đã hoạt động |
| 11 | `0800` | lỗi căn byte RMII RX |
| 12 | `1000` | lỗi căn byte RGMII RX |
| 13 | `2000` | FIFO overflow |
| 14 | `4000` | transmitter underflow |
| 15 | `8000` | dự phòng |

Giá trị cơ bản khỏe mạnh sau khởi động:

```text
DBG=0007
```

## 4. Diễn giải chiều máy A → máy B

```text
Máy A -> LAN8720 RX -> RMII deserializer -> FIFO -> RGMII serializer -> RTL8211F -> Máy B
```

| Giá trị | Kết luận |
|---|---|
| `0003` | reset/MDIO xong nhưng không thấy REF_CLK |
| `0007` | có REF_CLK nhưng LAN8720 chưa đưa CRS_DV vào FPGA |
| `000F` | thấy CRS_DV nhưng chưa giải mã được byte |
| `001F` | đã có byte nhưng chưa commit được frame hoàn chỉnh |
| `003F` | frame RMII hoàn chỉnh đã vào FIFO nhưng RGMII TX chưa chạy |
| `007F` | toàn bộ datapath FPGA chiều A→B đã hoạt động |

Nếu đạt `007F` nhưng máy B vẫn không thấy ARP, tập trung kiểm tra RGMII
electrical timing, clock/data delay, FCS và cấu hình thực của RTL8211F.

## 5. Diễn giải chiều máy B → máy A

Các bit cần lên lần lượt là 7, 8, 9 và 10. Nếu chỉ thử riêng chiều B→A, giá
trị cuối bình thường là:

```text
DBG=0787
```

Nếu đã thử thành công cả hai chiều, không có lỗi, status có thể đạt:

```text
DBG=07FF
```

## 6. Tìm COM và chạy decoder

PowerShell phải nhập lệnh theo đúng thứ tự trên một dòng. Nếu prompt xuất hiện
`>>`, nhấn `Ctrl+C` rồi nhập lại; không gõ ký hiệu `>>`.

Liệt kê COM:

```powershell
Get-CimInstance Win32_SerialPort | Format-Table DeviceID,Name,PNPDeviceID
```

Đóng PuTTY trước vì một COM không thể đồng thời được hai chương trình mở. Sau
đó chạy decoder, thay `COM17` bằng cổng thực tế:

```powershell
cd D:\TranDangNhatTan_24IC054_VKU\Junior\FPGA_MCU_IDS\ME\fpga\demo_connect\demo_connect; powershell -ExecutionPolicy Bypass -File .\tools\read_uart_debug.ps1 -Port COM17 -ShowAll
```

## 7. Khi UART không hiện gì

UART phải phát status mỗi giây dù Ethernet không có traffic. Không cần chạy
sender để kiểm tra UART.

Checklist:

1. Nạp đúng `release/demo_connect_uart_debug.fs` bằng SRAM Mode.
2. Xác nhận đang dùng đúng COM của USB-UART, không phải cổng thiết bị khác.
3. Đóng PuTTY trước khi chạy PowerShell decoder.
4. Kiểm tra TX FPGA nối sang RXD adapter và có GND chung.
5. PuTTY phải là 115200, 8-N-1, Flow Control `None`.
6. Đo TX idle: bình thường gần 3.3 V.
7. Test loopback adapter: tháo khỏi FPGA, nối TXD với RXD, mở PuTTY và gõ ký tự.

Nếu loopback không echo, lỗi thuộc COM/driver/USB-UART. Nếu loopback tốt nhưng
TX FPGA không có burst UART, kiểm tra bitstream, reset và chân V8.

## 8. Build và unit test

```powershell
cd D:\TranDangNhatTan_24IC054_VKU\Junior\FPGA_MCU_IDS\ME\fpga\demo_connect\demo_connect; .\run_uart_icarus.bat
cd D:\TranDangNhatTan_24IC054_VKU\Junior\FPGA_MCU_IDS\ME\fpga\demo_connect\demo_connect; .\run_gowin_release.bat
```

Kết quả mong đợi:

```text
UART_DEBUG_PASS message=DBG=A53C
Bitstream generation completed
RELEASE_BITSTREAM: release\demo_connect_uart_debug.fs
```

