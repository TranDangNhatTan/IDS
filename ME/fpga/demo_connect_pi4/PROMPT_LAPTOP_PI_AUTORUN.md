# Prompt cho AI tạo luồng laptop tự kết nối Pi và kiểm tra FPGA

Bạn là kỹ sư tích hợp Windows, Raspberry Pi 4 và FPGA Gowin.

Kiến trúc phần cứng cố định:

```text
Pi GPIO14/TXD0 -> ACG525 P6-GPIO0 -> FPGA C17 (uart_rx_pi)
FPGA V8 (uart_tx_pc) -> CH9102F onboard -> USB -> laptop COM
Pi GND <-> ACG525 GND
```

Không giả định Pi nhận ACK. Laptop phải đọc dữ liệu FPGA phát ra qua CH9102F.
UART là raw binary `115200 8N1`, không ASCII, không newline, không flow control.

Hãy tạo một workflow Windows tự động:

1. Đọc `connection.json` để lấy Pi host/user, thư mục project, COM port, baud,
   danh sách byte kiểm thử và timeout; không hardcode các giá trị này.
2. Ping Pi, kiểm tra SSH, kiểm tra `/dev/serial0` và kiểm tra Windows COM.
3. Mở COM ở 115200/8N1/No flow control.
4. SSH vào Pi và chạy `uart_tx_pi.py` với các byte:
   `55,AA,00,FF,A5,5A`.
5. Đọc byte nhị phân từ COM trên laptop và in HEX có timestamp.
6. Chỉ PASS khi nhận đúng đủ và đúng thứ tự; PuTTY trống không được coi là
   bằng chứng FPGA không nhận vì dữ liệu là raw binary.
7. Đóng COM, dừng SSH khi kết thúc, xử lý Ctrl+C và trả exit code 0/1.
8. Phân loại lỗi thành: Pi unreachable, SSH failed, serial0 missing, COM busy,
   FPGA bitstream/wiring/baud lỗi, timeout hoặc byte mismatch.

Không sửa project FPGA khác. Các file phải nằm trong
`ME/fpga/demo_connect_pi4/`. Xuất code, cấu hình và hướng dẫn chạy một lệnh.
