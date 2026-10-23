# ACG525 onboard RTL8211F UDP echo demo

Project kiểm tra Ethernet bằng cổng RJ45 tích hợp trên board ACG525. PHY onboard
là **RTL8211F**, giao tiếp với FPGA qua **RGMII 2.5 V**. Project không sử dụng
module LAN8720 ngoài hoặc các chân RMII trên P6.

Laptop gửi UDP broadcast tới `192.168.50.255:55002`, payload gồm `PING` và
sequence 32-bit little-endian. FPGA học MAC, IP và UDP source port rồi trả
`ACK1 + sequence` từ địa chỉ `192.168.50.50:55003`. Demo không triển khai ARP,
vì vậy phải gửi broadcast thay vì IP unicast của FPGA.

## Luồng phần cứng

```text
RJ45 onboard -> RTL8211F -> RGMII RX -> parser Ethernet/IPv4/UDP
             <- RTL8211F <- RGMII TX <- ACK Ethernet/IPv4/UDP
```

RTL giữ PHY reset khoảng 20 ms, sau đó dùng MDIO để tắt Gigabit và quảng bá
100BASE-TX full-duplex. Điều này phù hợp với các khối RGMII 25 MHz của project.

## LED

| LED | Ý nghĩa |
|---|---|
| LED0 | heartbeat clock hệ thống 50 MHz, đổi trạng thái khoảng mỗi 0,67 giây |
| LED1 | nhấp nháy cùng LED0 khi reset RTL8211F đã được nhả |
| LED2 | nhấp nháy cùng LED0 khi chuỗi MDIO (100BASE-TX full duplex) đã gửi xong |
| LED3 | nhấp nháy cùng LED0 khi đã quan sát được RGMII RX clock từ RTL8211F |

## Constraints theo schematic ACG525

- TXD0..3: `D2, D1, F2, F1`
- TX_CTL / TX_CLK: `C2, C1`
- RXD0..3: `G3, G1, F6, F5`
- RX_CTL / RX_CLK: `E1, L5`
- PHY reset / MDC / MDIO: `G6, D3, E4`
- Tất cả RGMII/MDIO dùng `LVCMOS25`.
- Clock hệ thống: `T9`, `LVCMOS33`.
- LED0..3: `D14, C14, B9, A9`, `LVCMOS15`.

File áp dụng là `src/demo_connect_onboard.cst`. Không dùng CST RMII/LAN8720 cũ.

## Kiểm tra và build

```powershell
cd D:\TranDangNhatTan_24IC054_VKU\Junior\FPGA_MCU_IDS\ME\fpga\demo_connect
powershell -ExecutionPolicy Bypass -File .\scripts\run_all_self_checks.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\build_gowin.ps1
```

Hoặc chạy cả hai bằng một lệnh:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\build_test_onboard.ps1
```

Testbench đúng phải in `UDP_ECHO_RGMII_PASS`. Bitstream được tạo tại
`impl\pnr\demo_connect.fs`.

## Kiểm tra với board

Sau khi nạp bitstream mới vào SRAM, chờ PHY thương lượng lại link rồi chạy:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run_udp_check.ps1 -Target 192.168.50.255 -Count 10 -ReplyPort 55103
```

Kết quả hoàn chỉnh phải có `ack=10` và `missing=[]`.
