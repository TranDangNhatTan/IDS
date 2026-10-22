# ACG525 onboard RTL8211F to external LAN8720 bridge

Project này dùng đúng hai cổng Ethernet:

- cổng RJ45 có sẵn trên ACG525 qua PHY RTL8211F/RGMII;
- một module LAN8720 ngoài qua RMII trên đầu nối P6.

Không cần module LAN8720 thứ hai. Bridge hoạt động hai chiều theo kiểu
store-and-forward, với hai asynchronous FIFO 2048 x 9 bit. RTL8211F được cấu
hình qua MDIO chỉ quảng bá 100BASE-TX full-duplex để cùng tốc độ với LAN8720.

## Nối một module LAN8720

Tắt nguồn trước khi nối. Nối GND của module với GND ACG525 và cấp 3.3 V đúng
theo ký hiệu nguồn trên carrier board. Không cấp 5 V vào các chân RMII.

| LAN8720 | ACG525 | FPGA | Hướng đối với FPGA |
|---|---|---|---|
| RXD0 | GPIO0 / P6-1 | C17 | input |
| RXD1 | GPIO1 / P6-2 | C18 | input |
| CRS_DV | GPIO2 / P6-3 | F14 | input |
| TXD0 | GPIO3 / P6-4 | G14 | output |
| TXD1 | GPIO4 / P6-5 | D17 | output |
| TX_EN | GPIO5 / P6-6 | D18 | output |
| REF_CLK 50 MHz | GPIO12 / P6-15 | K15/GCLKT_5 | input |

`REF_CLK` không dùng P6-8. Nó được chuyển sang P6-15 vì K15 là chân clock
chuyên dụng. Module LAN8720 phải được strap/cấu hình để **phát 50 MHz REF_CLK
vào FPGA**. Module trong ảnh không có chân reset riêng; để trống `NC`, `MDC`
và `MDIO`. Chân kết hợp `nINT/REFCLK` chỉ được dùng làm `REF_CLK`.

Cổng Ethernet tích hợp trên ACG525 đã nối cứng với FPGA; chỉ cần cắm cáp RJ45,
không đi dây RGMII bằng jumper.

## Kiểm tra và build

Từ Windows CMD hoặc PowerShell tại thư mục project:

```bat
run_icarus.bat
run_gowin_release.bat
```

Kết quả mô phỏng mong đợi:

```text
RGMII_RMII_BRIDGE_PASS frames=2 bytes=30 cdc=async
```

Bitstream release sinh ra tại `impl/pnr/demo_connect_release.fs`. Tên riêng
này giúp tránh Gowin GUI cũ ghi đè artifact đúng bằng netlist RMII hai cổng cũ.

Build đã được kiểm tra bằng Gowin EDA V1.9.11.03 Education cho
`GW5A-LV25UG324C2/I1`, device version B:

| Mục | Kết quả |
|---|---:|
| Logic | 575 / 23,040 (3%) |
| Register | 383 / 23,685 (2%) |
| BSRAM | 6 / 56 (11%) |
| Setup violations | 0 |
| Hold violations | 0 |
| Fmax miền 50 MHz chậm nhất | 154.834 MHz |

## LED trạng thái

- LED0: hai PHY đã thoát reset;
- LED1: chuỗi khởi tạo MDIO của RTL8211F hoàn tất;
- LED2: lỗi FIFO underflow/overflow;
- LED3: lỗi căn byte ở RX.

LED2 và LED3 phải tắt trong vận hành bình thường.

## Nạp thử an toàn

Nạp SRAM trước khi ghi flash:

1. Cấp nguồn board và nối USB-JTAG.
2. Mở Gowin Programmer, chọn **Scan Device** và kiểm tra GW5A-25.
3. Chọn **Edit > Configure Device**.
4. Chọn **SRAM Mode / SRAM Program**.
5. Chọn `impl/pnr/demo_connect_release.fs`, rồi **Program/Configure**.
6. Kiểm tra LED trạng thái và link LED ở cả hai cổng trước khi ping.

Sau khi chạy ổn định mới dùng **External Flash Mode 5A** để ghi cấu hình khởi
động. Không ghi flash trước lần thử SRAM đầu tiên.

## Giới hạn hiện tại

- Chỉ chạy 100 Mb/s full-duplex; không phải bridge Gigabit.
- FIFO phù hợp frame Ethernet chuẩn, không hỗ trợ jumbo frame trên 2048 byte.
- FPGA không kiểm CRC và không có MAC learning/filtering.
- Thiết kế đã qua simulation và place-and-route, nhưng vẫn cần kiểm tra thật
  với đúng revision carrier board và đúng strap clock của module LAN8720.
