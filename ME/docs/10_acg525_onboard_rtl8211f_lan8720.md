# ACG525: RTL8211F tích hợp ↔ một LAN8720 ngoài

Tài liệu cũ dùng hai LAN8720 ngoài đã được thay thế. Project hiện tại nằm ở
`ME/fpga/demo_connect/demo_connect` và dùng:

```text
RJ45 onboard -> RTL8211F/RGMII -> async FIFO -> LAN8720/RMII -> RJ45 ngoài
RJ45 ngoài   -> LAN8720/RMII   -> async FIFO -> RTL8211F/RGMII -> RJ45 onboard
```

## Kiến trúc

- `top_acg525_rgmii_rmii_bridge.v`: top, reset PHY 10 ms và kết nối hai hướng.
- `rtl8211f_mdio_init.v`: tắt quảng bá Gigabit, chỉ quảng bá 100BASE-TX FD và
  restart auto-negotiation.
- `rgmii_100_deserializer.v`, `rgmii_100_serializer.v`: chuyển byte/RGMII ở
  chế độ 100 Mb/s.
- `rmii_deserializer.v`, `rmii_serializer.v`: chuyển byte/RMII 50 MHz.
- `async_packet_fifo.v`: FIFO frame 2048 x 9, bit thứ 9 đánh dấu byte cuối.
- `demo_connect.cst`: pin onboard đã đối chiếu schematic và pin P6.
- `bridge_clocks.sdc`: ba miền clock bất đồng bộ.

TX RGMII không dùng một FF làm clock nội bộ. FSM chạy ở clock hệ thống 50 MHz;
clock 25 MHz chỉ được forward ra RTL8211F, còn dữ liệu đổi ở pha cạnh xuống để
có nửa chu kỳ ổn định trước cạnh lấy mẫu tiếp theo.

## Nối module ngoài

| Tín hiệu module | P6 | GPIO | Chân FPGA |
|---|---:|---:|---:|
| RXD0 | 1 | 0 | C17 |
| RXD1 | 2 | 1 | C18 |
| CRS_DV | 3 | 2 | F14 |
| TXD0 | 4 | 3 | G14 |
| TXD1 | 5 | 4 | D17 |
| TX_EN | 6 | 5 | D18 |
| REF_CLK 50 MHz | 15 | 12 | K15 |

K15 là `GCLKT_5`, vì vậy REF_CLK không còn đặt ở GPIO7/P6-8. Nối chung GND và
cấp 3.3 V cho LAN8720 từ chân nguồn được ghi rõ trên carrier board. Module phải
phát REF_CLK 50 MHz; thiết kế này không lái clock sang module. Module trong ảnh
không có reset riêng; để trống `NC`, `MDC` và `MDIO`, còn `nINT/REFCLK` được
dùng làm ngõ ra clock.

## Xác minh

```bat
cd ME\fpga\demo_connect\demo_connect
run_icarus.bat
run_gowin_release.bat
```

Icarus đã truyền đồng thời hai frame qua các miền clock độc lập và báo:

```text
RGMII_RMII_BRIDGE_PASS frames=2 bytes=30 cdc=async
```

Gowin synthesis, place, route, timing và bitstream đều hoàn tất. Báo cáo cuối
cùng có 0 setup violation, 0 hold violation, dùng 575 logic, 383 register và 6
BSRAM. File nạp SRAM là `impl/pnr/demo_connect_release.fs`.

## Lưu ý khi thử thật

1. Tắt nguồn trước khi đi dây.
2. Thử nạp SRAM trước, chưa ghi external flash.
3. LED0 và LED1 phải sáng; LED2 và LED3 phải tắt.
4. Kiểm tra link LED hai cổng, sau đó mới chạy ping/Wireshark.
5. Nếu module ngoài không phát REF_CLK, phải đổi strap phần cứng hoặc sửa thiết
   kế clock; không được nối hai ngõ ra clock với nhau.
