# Nhật ký bring-up Ethernet ACG525: RTL8211F ↔ LAN8720

Tài liệu này ghi lại toàn bộ cấu hình, kết quả đo và lỗi đã gặp khi kiểm tra
bridge Ethernet hai chiều trên ACG525. Đây là trạng thái thực nghiệm hiện tại,
không phải kết luận bridge đã hoạt động end-to-end.

## 1. Topology thực tế

```text
Máy A 192.168.50.1/24
    |
    | RJ45
    v
LAN8720 ngoài -- RMII 50 MHz -- FPGA ACG525 -- RGMII 100 Mb/s -- RTL8211F onboard
                                                                    |
                                                                    | RJ45
                                                                    v
                                                        Máy B 192.168.50.2/24
```

Thiết kế là bridge store-and-forward hai chiều. Mỗi chiều dùng một FIFO frame
không đồng bộ 2048 x 9 bit. Bit thứ 9 đánh dấu byte cuối frame.

## 2. Target FPGA và project đúng

- FPGA: `GW5A-LV25UG324C2/I1`
- Device: `GW5A-25B`
- Device version trong Tcl: `B`
- Top module: `top_acg525_rgmii_rmii_bridge`
- Project chính: `ME/fpga/demo_connect/demo_connect`
- Project GUI sạch: `demo_connect_uart_debug.gprj`
- Script build: `run_gowin_release.bat`
- Output build tạm: `impl/pnr/demo_connect_release.fs`
- Bản sao ổn định để nạp: `release/demo_connect_uart_debug.fs`

SHA-256 của bitstream debug được build ngày 2026-10-15:

```text
3EC2AA5E03D8EBBA0E9EBB0A4C48F3ECFC3F4F67216EA26936726F8F3B6B97AC
```

Không nạp `demo_connect.fs`, vì tên này từng được Gowin GUI cũ tạo từ top
`top_ethernet_passthrough` và không phải thiết kế hiện tại.

`run_gowin_release.bat` tự sao chép output khỏi `impl/` sang `release/`. Việc
này tránh phiên Gowin GUI cũ xóa artifact khi tự clean/rebuild thư mục `impl`.

## 3. Kết nối LAN8720 ngoài

| LAN8720 | ACG525 | P6 | FPGA | Hướng so với FPGA |
|---|---|---:|---|---|
| RXD0 | GPIO0 | 1 | C17 | input |
| RXD1 | GPIO1 | 2 | C18 | input |
| CRS_DV/CRS | GPIO2 | 3 | F14 | input |
| TXD0 | GPIO3 | 4 | G14 | output |
| TXD1 | GPIO4 | 5 | D17 | output |
| TX_EN | GPIO5 | 6 | D18 | output |
| nINT/REFCLK | GPIO12 | 15 | K15 | input clock 50 MHz |
| GND | GND | - | - | nối chung mass |
| VCC | 3.3 V | - | - | không cấp 5 V vào RMII |

Các chân `NC`, `MDC`, `MDIO` trên module LAN8720 ngoài đang để trống. Module
phải phát `REF_CLK` 50 MHz vào FPGA. GPIO12 nằm ở P6 physical pin 15, không
phải P6-13.

RGMII onboard dùng bank 6/7 ở 2.5 V (`LVCMOS25`). RMII ngoài dùng bank 2 ở
3.3 V (`LVCMOS33`).

## 4. Cấu hình mạng đã thực hiện

### Máy A

- Adapter: `Ethernet`
- NIC: Realtek PCIe GbE Family Controller
- MAC: `C4-C6-E6-18-5D-9E`
- IPv4: `192.168.50.1/24`
- Trạng thái cuối: `Up`, `100 Mbps`

Lệnh cấu hình:

```powershell
Enable-NetAdapter -Name "Ethernet" -Confirm:$false
netsh interface ipv4 set address name="Ethernet" source=static address=192.168.50.1 mask=255.255.255.0 gateway=none
Get-NetAdapter -Name "Ethernet" | Format-Table Name,Status,LinkSpeed
Get-NetIPAddress -InterfaceAlias "Ethernet" -AddressFamily IPv4
```

Ban đầu adapter bị `Disabled`, sau đó `Disconnected`, rồi link ở `10 Mbps`.
RTL RMII hiện tại chỉ xử lý 100 Mb/s, vì vậy link 10 Mb/s không hợp lệ. Sau khi
chỉnh Speed & Duplex/link, kết quả cuối là `Up 100 Mbps`.

### Máy B

- Adapter: `Ethernet 2`
- NIC: Realtek USB FE Family Controller
- MAC: `00-E0-4C-36-25-7F`
- IPv4: `192.168.50.2/24`
- Trạng thái cuối: `Up`, `100 Mbps`

Máy B ban đầu nhận APIPA `169.254.176.172/16`. Đã thay bằng IP tĩnh:

```powershell
netsh interface ipv4 set address name="Ethernet 2" source=static address=192.168.50.2 mask=255.255.255.0 gateway=none
Get-NetIPAddress -InterfaceAlias "Ethernet 2" -AddressFamily IPv4 | Format-Table InterfaceAlias,IPAddress,PrefixLength
```

Máy B còn có `Network Bridge` ở `172.26.64.150/16`, nhưng subnet FPGA
`192.168.50.0/24` được route trực tiếp qua `Ethernet 2`.

## 5. Công cụ UDP

Source nằm trong:

```text
ME/sw/ethernet_test/
```

Các file chính:

- `send_to_external_module.py`: sender máy A.
- `receive_from_onboard_port.py`: receiver khi chạy từ repository.
- `udp_sender.py`, `udp_receiver.py`: engine UDP/CRC/pattern.
- `check_ethernet.py`: kiểm tra adapter, IP, port và ping.
- `protocol.py`: header, sequence, CRC32 và pattern.

Gói standalone để chép sang máy B:

```text
ME/transfer/MACHINE_B_RECEIVER/
ME/transfer/MACHINE_B_RECEIVER.zip
```

UDP port `5001` từng bị `lktsrv.exe` PID 7756 chiếm, gây `WinError 10048`.
Port test hiện tại là `55001`.

Lỗi `WinError 10049` có nghĩa script bind vào một IPv4 chưa được gán trên máy.
Không bỏ tùy chọn bind, vì bind bắt buộc traffic đi qua Ethernet thay vì Wi-Fi.

### Chạy test nhẹ đúng thứ tự

Trên máy B:

```powershell
python .\machine_b_receiver.py --expected 100 --idle-timeout 5
```

Trên máy A, tại root repository:

```powershell
.\.venv\Scripts\python.exe -m ME.sw.ethernet_test.send_to_external_module --count 100 --rate-mbps 1
```

Firewall máy B nếu cần:

```powershell
New-NetFirewallRule -DisplayName "FPGA UDP Receiver 55001" -Direction Inbound -Protocol UDP -LocalPort 55001 -Action Allow -Profile Any
```

Sender đã chạy thành công ở mức phần mềm:

```text
packets=100, payload=1400 B
Done: sent=100, UDP_bytes=144000, elapsed=1.175 s, rate=0.980 Mbps
```

Trước đó sender cũng đã gửi 1000 datagram ở khoảng 9.804 Mbps. Dòng `Done`
chỉ xác nhận Windows đã nhận datagram từ Python, không xác nhận máy B nhận được.

## 6. Kết quả mạng thực tế hiện tại

Máy B không xuất hiện dòng `Receiving session=...`; receiver chỉ đứng ở:

```text
Listening on 192.168.50.2:55001
```

Ping từ B tới A mất 100%:

```text
Packets: Sent = 4, Received = 0, Lost = 4 (100% loss)
```

Neighbor table ở cả hai đầu:

```text
Máy A: 192.168.50.2  00-00-00-00-00-00  Unreachable
Máy B: 192.168.50.1  00-00-00-00-00-00  Unreachable
```

Kết luận: ARP chưa đi qua FPGA. Lỗi hiện tại nằm ở layer 2 phần cứng/RTL, không
phải IP, UDP port, payload Python hay firewall. Hai copper link đều đã lên
100 Mbps, nhưng link up không chứng minh MAC-side RMII/RGMII đang truyền frame.

## 7. MDIO RTL8211F

Phiên bản cũ phát MDIO tới PHY address `00000`. Source hiện tại đã đổi thành
parameter mặc định:

```verilog
parameter [4:0] PHY_ADDR = 5'b00001
```

Chuỗi ghi:

- register 9 = `0x0000`: tắt quảng bá Gigabit;
- register 4 = `0x0101`: quảng bá 100BASE-TX full-duplex;
- register 0 = `0x1200`: enable/restart auto-negotiation.

Giới hạn: `mdio_init_done` hiện chỉ báo FSM đã phát xong ba write frame; thiết
kế chưa đọc lại register PHY để xác nhận nội dung.

## 8. Lỗi Gowin GUI đã gặp

Triệu chứng:

```text
Reading netlist ... impl/gwsynthesis/demo_connect.vg
ERROR (CT1135): Can't find object named 'sys_clk_50'
ERROR (CT1135): Can't find object named 'lan_rxd[0]'
ERROR (CT1135): Can't find object named 'uart_tx'
...
```

Nguyên nhân: phiên Gowin GUI cũ tự thêm lại các file/top dual-RMII cũ, bật
`rmii_50mhz.sdc`, tắt `bridge_clocks.sdc` và compile top không khớp CST.

Cách tránh:

1. Đóng Gowin GUI cũ và chọn `Don't Save` nếu được hỏi.
2. Mở `demo_connect_uart_debug.gprj`.
3. Top phải là `top_acg525_rgmii_rmii_bridge`.
4. Project không được chứa `top_ethernet_passthrough.v`.
5. Hoặc bỏ qua GUI và build bằng một dòng:

```powershell
cd D:\TranDangNhatTan_24IC054_VKU\Junior\FPGA_MCU_IDS\ME\fpga\demo_connect\demo_connect; .\run_gowin_release.bat
```

Build đúng phải có:

```text
Current top module is "top_acg525_rgmii_rmii_bridge"
Physical Constraint parsed completed
Placement and routing completed
Bitstream generation completed
```

Resource của bản có UART debug: 765 logic, 535 register, 6 BSRAM.

## 9. Simulation đã pass

```powershell
cd D:\TranDangNhatTan_24IC054_VKU\Junior\FPGA_MCU_IDS\ME\fpga\demo_connect\demo_connect; .\run_icarus.bat
cd D:\TranDangNhatTan_24IC054_VKU\Junior\FPGA_MCU_IDS\ME\fpga\demo_connect\demo_connect; .\run_uart_icarus.bat
```

Kết quả:

```text
RGMII_RMII_BRIDGE_PASS frames=2 bytes=30 cdc=async
UART_DEBUG_PASS message=DBG=A53C
```

Simulation dùng PHY stimulus lý tưởng; nó không xác minh dây thật, clock thật,
RGMII clock/data skew hoặc MDIO readback.

## 10. Trạng thái cần làm tiếp

UART debug đã được thêm để xác định frame dừng ở đâu. Ở checkpoint hiện tại,
PuTTY mở được `COM17` nhưng chưa hiện ký tự. Cần xác minh COM17, dây TX→RX,
GND, bitstream đã nạp và chân TX idle trước khi debug Ethernet tiếp.

Không cần tiếp tục gửi UDP cho tới khi UART xuất được ít nhất `DBG=0007`.

## 11. Ket qua end-to-end ngay 2026-10-21

Bridge da duoc build lai tu project `demo_connect_uart_debug.gprj`, chay hai
regression va nap SRAM thanh cong:

```text
RGMII_RMII_BRIDGE_PASS frames=2 bytes=30 cdc=async
UART_DEBUG_PASS message=DBG=A53C
SRAM Program: Finished
```

Bitstream dang chay:

```text
release/demo_connect_uart_debug.fs
SHA-256: B5746B301162F2817FE4D6BB5F6B616E16D9E1F7BF4AEA1227744027C3616CAA
```

Hai may duoc cau hinh cung subnet, khong gateway:

```text
Machine A / Ethernet  : 192.168.50.1/24, Up 100 Mbps
Machine B / Ethernet 2: 192.168.50.2/24, Up 100 Mbps
```

Sau khi xoa neighbor cu va ping lai, ARP da hoc dung MAC cua Machine B va
ping end-to-end pass:

```text
192.168.50.2  00-E0-4C-36-25-7F  Reachable
Packets: Sent = 8, Received = 8, Lost = 0 (0% loss)
Minimum = 1 ms, Maximum = 1 ms, Average = 1 ms
```

Echo request di theo huong RMII -> FPGA -> RGMII va echo reply quay lai theo
huong RGMII -> FPGA -> RMII, vi vay ket qua nay xac minh ca hai chieu bridge.

LED trong bitstream nay la cac co sticky cho huong Machine A -> Machine B:

```text
LED0: bitstream/LED baseline (constant 1)
LED1: external RMII CRS_DV seen
LED2: complete external RMII frame seen
LED3: onboard RGMII TX_CTL seen
```

