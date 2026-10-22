# Kiểm tra Ethernet bridge bằng UDP

Hai máy phải đặt IPv4 cùng subnet, ví dụ:

- máy nhận: `192.168.50.2/24`;
- máy gửi: `192.168.50.1/24`.

Kiểm tra link Ethernet, địa chỉ IPv4 và UDP port trước:

```bat
.\.venv\Scripts\python.exe -m ME.sw.ethernet_test.check_ethernet --adapter Ethernet --port 5001 --target 192.168.50.1
```

Trên máy còn lại, đổi `--target` thành địa chỉ của máy này.

Trên máy nhận, chạy từ thư mục gốc repository:

```bat
.\.venv\Scripts\python.exe -m ME.sw.ethernet_test.udp_receiver --bind 0.0.0.0 --port 5001 --expected 1000 --verify-pattern
```

Cho phép UDP port 5001 qua Windows Firewall khi Windows hỏi. Sau đó trên máy
gửi, thay địa chỉ `--host` bằng IPv4 của máy nhận:

```bat
.\.venv\Scripts\python.exe -m ME.sw.ethernet_test.udp_sender --host 192.168.50.2 --port 5001 --count 1000 --payload-size 1400 --rate-mbps 10
```

Kết quả tốt là `missing packets`, `CRC errors` và `pattern errors` đều bằng 0.
Sau lần đầu, có thể tăng dần `--rate-mbps` lên 25, 50 rồi 80 để stress test.

## Hai tool theo đúng hai cổng của FPGA

Topology:

```text
Máy A 192.168.50.1 -> LAN8720 ngoài -> FPGA -> RJ45 onboard -> Máy B 192.168.50.2
```

Chạy trên máy B trước:

```bat
.\.venv\Scripts\python.exe -m ME.sw.ethernet_test.receive_from_onboard_port
```

Sau đó chạy trên máy A:

```bat
.\.venv\Scripts\python.exe -m ME.sw.ethernet_test.send_to_external_module
```

Hai tool mặc định gửi 1000 gói, payload 1400 byte, tốc độ 10 Mbps và dùng UDP
port 55001. Có thể đổi bằng các tùy chọn `--count`, `--payload-size`,
`--rate-mbps` và `--port`.
