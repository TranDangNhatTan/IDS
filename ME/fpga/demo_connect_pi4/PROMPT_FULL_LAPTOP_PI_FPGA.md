# Prompt triển khai đồng bộ Laptop – Raspberry Pi 4 – FPGA ACG525

Bạn là kỹ sư tích hợp Windows, Raspberry Pi 4 và FPGA Gowin. Hãy triển khai
đúng một hệ thống kiểm thử end-to-end trong thư mục
`ME/fpga/demo_connect_pi4/`; không sửa bất kỳ project FPGA nào khác.

## Kiến trúc bắt buộc

```text
Raspberry Pi GPIO14/TXD0 (physical pin 8)
    -> ACG525 P6-GPIO0 -> FPGA C17 -> uart_rx_pi
    -> uart_forwarder (FPGA)
    -> FPGA V8 -> CH9102F onboard -> USB -> laptop COM
Raspberry Pi GND (physical pin 6) -> ACG525 GND
```

Pi chỉ phát UART vào FPGA. FPGA nhận từng byte raw rồi phát lại byte đó qua
V8 để laptop đọc. Không giả định Pi nhận ACK và không dùng Ethernet cho đường
data này.

## FPGA phải khớp tuyệt đối

- Device: `GW5A-LV25UG324C2/I1`, device version B.
- Clock: 50 MHz tại T9.
- Reset active-low: B16, `LVCMOS15`, `PULL_MODE=UP`.
- UART RX từ Pi: C17, `LVCMOS33`, `PULL_MODE=UP`.
- UART TX đến CH9102F: V8, `LVCMOS33`, `PULL_MODE=UP`, drive 8.
- UART: 115200 baud, 8 data bits, no parity, 1 stop bit, idle high.
- RX phải có 2-FF synchronizer và center sampling.
- TX/RX chỉ dùng clock 50 MHz và counter, không tạo derived/gated clock.
- Dùng FIFO tối thiểu 4 byte giữa RX và TX để không mất byte khi TX bận.

## Laptop phải tự chạy

Tạo hoặc kiểm tra các file sau:

```text
src/uart_rx.v
src/uart_tx.v
src/uart_forwarder.v
constraints/acg525.cst
constraints/acg525.sdc
demo_rpi4/uart_tx_pi.py
connection.json
scripts/run_pi_fpga_test.ps1
```

`connection.json` phải chứa Pi host, Pi user, thư mục script trên Pi, COM
CH9102F, baud, timeout và danh sách byte test. Không hardcode các giá trị này
trong script.

`run_pi_fpga_test.ps1` phải:

1. Đọc `connection.json`.
2. Ping Pi và kiểm tra SSH.
3. Kiểm tra `/dev/serial0` trên Pi.
4. Mở COM CH9102F trên laptop ở 115200/8N1/no flow control.
5. SSH vào Pi và chạy `uart_tx_pi.py`.
6. Đọc raw binary từ COM, in HEX có timestamp.
7. Xác minh chính xác chuỗi:
   `55 AA 00 FF A5 5A`.
8. Báo lỗi riêng cho Pi unreachable, SSH lỗi, COM bận, timeout, sai byte,
   sai dây, sai baud hoặc FPGA chưa được nạp.
9. Đóng COM và dừng tiến trình SSH khi kết thúc.
10. Chỉ in `RESULT=PASS` khi đủ byte và đúng thứ tự.

Không dùng PuTTY để quyết định dữ liệu binary có hợp lệ hay không; byte `00`,
`A5`, `FF` có thể không hiển thị trên terminal.

## Bàn giao bắt buộc

- Self-checking simulation phải PASS.
- Gowin synthesis/P&R phải PASS cho đúng device.
- Setup violations = 0, hold violations = 0.
- Pin report phải xác nhận T9/B16/C17/V8.
- Bitstream phải nằm trong `release/uart_forwarder.fs`.
- README phải ghi rõ đấu dây, SSH, cài PySerial và lệnh chạy duy nhất trên
  laptop.
- Không được tuyên bố PASS nếu chưa có log simulation và timing thực tế.
