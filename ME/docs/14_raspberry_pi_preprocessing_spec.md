# SPEC KỸ THUẬT: PHẦN MỀM TIỀN XỬ LÝ IDS & DASHBOARD TRÊN RASPBERRY PI

> **Tài liệu bàn giao cho Agent / Lập trình viên Python/C++ trên Raspberry Pi**  
> Dự án: FPGA-Accelerated Network Intrusion Detection System (NSL-KDD `fpga_flow28`)  
> Mô hình: **Passive NIDS (Out-of-band qua Switch Port Mirroring / SPAN)**  
> Giao tiếp: Raspberry Pi nhận gói tin từ cổng LAN $\rightarrow$ Tiền xử lý thành 28 đặc trưng (77 bytes) $\rightarrow$ Gửi sang FPGA qua UART $\rightarrow$ Nhận Class ID từ FPGA $\rightarrow$ Hiển thị Web Dashboard Real-time.

---

## 1. TỔNG QUAN HỆ THỐNG & LUỒNG DỮ LIỆU

```
   [Switch SPAN Port] 
          │ 
          ▼ (1 Cáp mạng RJ45 vào cổng eth0 của Pi)
┌────────────────────────────────────────────────────────────────────────┐
│                        RASPBERRY PI (PI 4 / PI 5)                      │
│                                                                        │
│  [Thread 1: Packet Capture (Promiscuous Mode)]                         │
│       │ Bóc tách L2-L4 (IP, Port, TCP flags, Packet Size)              │
│       ▼                                                                │
│  [Thread 2: Flow Table & Sliding Window Engine]                        │
│       │ Theo dõi phiên kết nối + Cửa sổ 2s + Cửa sổ 100 host           │
│       ▼                                                                │
│  [Thread 3: Quantizer & 616-bit Bit-Packing]                           │
│       │ Lượng tử hóa 28 trường theo chuẩn fpga_flow28                  │
│       │ Đóng gói thành mảng 77 bytes (616 bits)                        │
│       ▼                                                                │
│  [Thread 4: UART Communication Manager (/dev/serial0)]                 │
│       │ ──► Gửi Khung 80 Bytes: [0xAA, 0x55, 77B Data, Checksum] ──► │
│       │ ◄── Nhận Khung 3 Bytes: [0xBB, Class_ID, Checksum] ◄──────── │
│       ▼                                                                │
│  [Thread 5: Web Dashboard & Alert Server (WebSocket / HTTP)]           │
└───────┬────────────────────────────────────────────────────────────────┘
        │ UART TX/RX (921.600 baud, 3 dây: TX, RX, GND)
        ▼
┌────────────────────────────────────────────────────────────────────────┐
│                          FPGA (GOWIN ACG525)                           │
│  - uart_feature_receiver: Nhận 80 bytes, trích xuất 616-bit            │
│  - ids_tree_engine: Duyệt 1 Decision Tree (1.273 nodes) trong < 1 µs   │
│  - uart_tx: Bắn mã class_id (0..39) ngược lại Raspberry Pi             │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. QUY CHUẨN 28 ĐẶC TRƯNG (`fpga_flow28`)

Mỗi vector trích xuất từ 1 phiên kết nối (connection) gồm đúng **28 đặc trưng** theo thứ tự từ ID 0 đến 27:

| ID | Tên Đặc Trưng | Kiểu dữ liệu | Quy Tắc Tính Toán / Lượng Tử Hóa | Bão Hòa (Saturate At) | Bit Width Slot |
|:--:|:---|:---:|:---|:---:|:---:|
| **0** | `duration` | Integer | Thời gian sống của kết nối (giây): $\min(\text{duration}, 16744)$ | 16.744 | 22 bit |
| **1** | `protocol_type` | Category | Tra bảng: `icmp`=1, `tcp`=2, `udp`=3 (Unknown=0) | 3 | 22 bit |
| **2** | `service` | Category | Tra bảng 70 dịch vụ mạng (1..70, Unknown=0) | 70 | 22 bit |
| **3** | `flag` | Category | Tra bảng 11 trạng thái cờ TCP (1..11, Unknown=0) | 11 | 22 bit |
| **4** | `src_bytes` | Integer | $\min(\text{bytes\_from\_src\_to\_dst} \gg 2,\, 240748)$ *(chia 4)* | 240.748 | 22 bit |
| **5** | `dst_bytes` | Integer | $\min(\text{bytes\_from\_dst\_to\_src} \gg 6,\, 3309)$ *(chia 64)* | 3.309 | 22 bit |
| **6** | `land` | Boolean | $1$ nếu $(\text{src\_ip} == \text{dst\_ip} \ \&\&\ \text{src\_port} == \text{dst\_port})$, ngược lại $0$ | 1 | 22 bit |
| **7** | `wrong_fragment` | Integer | $\min(\text{sum\_bad\_checksum\_or\_fragments}, 3)$ | 3 | 22 bit |
| **8** | `urgent` | Integer | $\min(\text{urgent\_packets\_count}, 1)$ | 1 | 22 bit |
| **9** | `count` | Integer | Số kết nối tới cùng IP đích trong **2 giây qua**: $\min(N, 511)$ | 511 | 22 bit |
| **10** | `srv_count` | Integer | Số kết nối tới cùng Port/Service trong **2 giây qua**: $\min(N, 100)$ | 100 | 22 bit |
| **11** | `serror_rate` | Rate (Q0.16) | Tỷ lệ kết nối có lỗi SYN (flag S0, S1, S2, S3) trong 2s: $\text{round}(v \times 65535)$ | 65.535 | 22 bit |
| **12** | `srv_serror_rate` | Rate (Q0.16) | Tỷ lệ lỗi SYN của cùng service trong 2s: $\text{round}(v \times 65535)$ | 65.535 | 22 bit |
| **13** | `rerror_rate` | Rate (Q0.16) | Tỷ lệ kết nối bị từ chối (REJ) trong 2s: $\text{round}(v \times 65535)$ | 65.535 | 22 bit |
| **14** | `srv_rerror_rate` | Rate (Q0.16) | Tỷ lệ lỗi REJ của cùng service trong 2s: $\text{round}(v \times 65535)$ | 65.535 | 22 bit |
| **15** | `same_srv_rate` | Rate (Q0.16) | Tỷ lệ kết nối tới cùng service trong 2s: $\text{round}(v \times 65535)$ | 65.535 | 22 bit |
| **16** | `diff_srv_rate` | Rate (Q0.16) | Tỷ lệ kết nối tới các service khác nhau trong 2s: $\text{round}(v \times 65535)$ | 65.535 | 22 bit |
| **17** | `srv_diff_host_rate`| Rate (Q0.16) | Tỷ lệ kết nối cùng service nhưng tới các host khác nhau trong 2s: $\text{round}(v \times 65535)$| 65.535 | 22 bit |
| **18** | `dst_host_count` | Integer | Số kết nối cùng IP đích trong **100 kết nối gần nhất**: $\min(N, 253)$ | 253 | 22 bit |
| **19** | `dst_host_srv_count`| Integer | Số kết nối cùng IP đích & cùng service trong **100 kết nối gần nhất**: $\min(N, 255)$ | 255 | 22 bit |
| **20** | `dst_host_same_srv_rate` | Rate (Q0.16) | Tỷ lệ cùng service trong 100 kết nối gần nhất: $\text{round}(v \times 65535)$ | 65.535 | 22 bit |
| **21** | `dst_host_diff_srv_rate` | Rate (Q0.16) | Tỷ lệ khác service trong 100 kết nối gần nhất: $\text{round}(v \times 65535)$ | 65.535 | 22 bit |
| **22** | `dst_host_same_src_port_rate`| Rate (Q0.16)| Tỷ lệ cùng port nguồn trong 100 kết nối gần nhất: $\text{round}(v \times 65535)$ | 65.535 | 22 bit |
| **23** | `dst_host_srv_diff_host_rate`| Rate (Q0.16)| Tỷ lệ cùng service nhưng khác host trong 100 kết nối gần nhất: $\text{round}(v \times 65535)$ | 65.535 | 22 bit |
| **24** | `dst_host_serror_rate` | Rate (Q0.16) | Tỷ lệ lỗi SYN trong 100 kết nối gần nhất: $\text{round}(v \times 65535)$ | 65.535 | 22 bit |
| **25** | `dst_host_srv_serror_rate` | Rate (Q0.16)| Tỷ lệ lỗi SYN cùng service trong 100 kết nối gần nhất: $\text{round}(v \times 65535)$ | 65.535 | 22 bit |
| **26** | `dst_host_rerror_rate` | Rate (Q0.16) | Tỷ lệ lỗi REJ trong 100 kết nối gần nhất: $\text{round}(v \times 65535)$ | 65.535 | 22 bit |
| **27** | `dst_host_srv_rerror_rate` | Rate (Q0.16)| Tỷ lệ lỗi REJ cùng service trong 100 kết nối gần nhất: $\text{round}(v \times 65535)$ | 65.535 | 22 bit |

---

## 3. BẢNG MAPPING CATEGORICAL (PYTHON DICTIONARIES)

```python
PROTOCOL_MAP = {
    "icmp": 1,
    "tcp": 2,
    "udp": 3
}

FLAG_MAP = {
    "OTH": 1, "REJ": 2, "RSTO": 3, "RSTOS0": 4, "RSTR": 5,
    "S0": 6, "S1": 7, "S2": 8, "S3": 9, "SF": 10, "SH": 11
}

# 70 Services chuẩn NSL-KDD (Trích xuất từ fpga_category_codes.csv)
SERVICE_MAP = {
    "IRC": 1, "X11": 2, "Z39_50": 3, "aol": 4, "auth": 5, "bgp": 6, "courier": 7,
    "csnet_ns": 8, "ctf": 9, "daytime": 10, "discard": 11, "domain": 12, "domain_u": 13,
    "echo": 14, "eco_i": 15, "ecr_i": 16, "efs": 17, "exec": 18, "finger": 19,
    "ftp": 20, "ftp_data": 21, "gopher": 22, "harvest": 23, "hostnames": 24, "http": 25,
    "http_2784": 26, "http_443": 27, "http_8001": 28, "imap4": 29, "iso_tsap": 30,
    "klogin": 31, "kshell": 32, "ldap": 33, "link": 34, "login": 35, "mtp": 36,
    "name": 37, "netbios_dgm": 38, "netbios_ns": 39, "netbios_ssn": 40, "netstat": 41,
    "nnsp": 42, "nntp": 43, "ntp_u": 44, "other": 45, "pm_dump": 46, "pop_2": 47,
    "pop_3": 48, "printer": 49, "private": 50, "red_i": 51, "remote_job": 52, "rje": 53,
    "shell": 54, "smtp": 55, "sql_net": 56, "ssh": 57, "sunrpc": 58, "supdup": 59,
    "systat": 60, "telnet": 61, "tftp_u": 62, "tim_i": 63, "time": 64, "urh_i": 65,
    "urp_i": 66, "uucp": 67, "uucp_path": 68, "vmnet": 69, "whois": 70
}
```

---

## 4. QUY CÁCH ĐÓNG GÓI 616-BIT & KHUNG TRUYỀN UART

### 4.1 Thuật toán Bit-Packing (616 bits = 77 Bytes)
FPGA yêu cầu 28 đặc trưng được zero-extended thành **22 bit/đặc trưng**.  
Toàn bộ 616 bit được nhồi theo thứ tự Little-Endian Bit-stream:

```python
def pack_features_616bits(features: list[int]) -> bytes:
    """
    features: List 28 số nguyên (đã lượng tử hóa) theo đúng thứ tự ID 0 -> 27.
    Trả về: bytearray 77 bytes đúng chuẩn nạp vào FPGA snapshot register.
    """
    assert len(features) == 28
    bit_array = 0
    total_bits = 0
    
    for i, val in enumerate(features):
        val_22bit = val & 0x3FFFFF  # Lấy đúng 22-bit
        bit_array |= (val_22bit << total_bits)
        total_bits += 22  # Tổng 28 * 22 = 616 bits

    # Chuyển integer 616-bit thành 77 bytes (Little-Endian)
    payload = bit_array.to_bytes(77, byteorder='little')
    return payload
```

### 4.2 Giao thức Khung UART (Full-Duplex)
* **Cấu hình Port:** `/dev/serial0` (hoặc `/dev/ttyAMA0`), Baudrate: **`921.600`**, `8-N-1`.

#### Chiều Pi $\rightarrow$ FPGA (Khung 80 Bytes):
```
┌──────────────┬──────────────┬───────────────────────────────┬────────────┐
│ Byte 0       │ Byte 1       │ Bytes 2 .. 78                 │ Byte 79    │
│ Sync 1 (0xAA)│ Sync 2 (0x55)│ 77 Bytes Feature Payload      │ XOR Check  │
└──────────────┴──────────────┴───────────────────────────────┴────────────┘
```
$$\text{Checksum} = \text{payload}[0] \oplus \text{payload}[1] \oplus \dots \oplus \text{payload}[76]$$

#### Chiều FPGA $\rightarrow$ Pi (Khung 3 Bytes trả về kết quả):
```
┌──────────────┬───────────────────────────────┬────────────┐
│ Byte 0       │ Byte 1                        │ Byte 2     │
│ Sync (0xBB)  │ Class ID (0 .. 39)            │ Checksum   │
└──────────────┴───────────────────────────────┴────────────┘
```

---

## 5. BẢNG MÃ 40 NHÃN LỚP (CLASS ID MAPPER)

Trích xuất từ `ME/config/class_map.json`:

```python
CLASS_MAP = {
    0: "apache2", 1: "back", 2: "buffer_overflow", 3: "ftp_write", 4: "guess_passwd",
    5: "httptunnel", 6: "imap", 7: "ipsweep", 8: "land", 9: "loadmodule",
    10: "mailbomb", 11: "mscan", 12: "multihop", 13: "named", 14: "neptune",
    15: "nmap", 16: "normal", 17: "perl", 18: "phf", 19: "pod",
    20: "portsweep", 21: "processtable", 22: "ps", 23: "rootkit", 24: "saint",
    25: "satan", 26: "sendmail", 27: "smurf", 28: "snmpgetattack", 29: "snmpguess",
    30: "spy", 31: "sqlattack", 32: "teardrop", 33: "udpstorm", 34: "warezclient",
    35: "warezmaster", 36: "worm", 37: "xlock", 38: "xsnoop", 39: "xterm"
}

# Phân loại theo họ tấn công
ATTACK_CATEGORIES = {
    "normal": "NORMAL",
    "neptune": "DoS", "smurf": "DoS", "back": "DoS", "teardrop": "DoS", "pod": "DoS", 
    "apache2": "DoS", "processtable": "DoS", "mailbomb": "DoS", "udpstorm": "DoS", "land": "DoS",
    "portsweep": "Probe", "ipsweep": "Probe", "satan": "Probe", "nmap": "Probe", "mscan": "Probe", "saint": "Probe",
    "guess_passwd": "R2L", "warezclient": "R2L", "warezmaster": "R2L", "snmpguess": "R2L", "snmpgetattack": "R2L", 
    "httptunnel": "R2L", "named": "R2L", "sendmail": "R2L", "ftp_write": "R2L", "imap": "R2L", "multihop": "R2L",
    "buffer_overflow": "U2R", "rootkit": "U2R", "loadmodule": "U2R", "xterm": "U2R", "perl": "U2R", "ps": "U2R", "sqlattack": "U2R"
}
```

---

## 6. KIẾN TRÚC CODE THAM KHẢO TRÊN RASPBERRY PI (PYTHON)

Agent lập trình có thể triển khai hệ thống thành các module sạch như sau:

### Cấu trúc thư mục khuyến nghị:
```text
pi_ids_app/
├── main.py                  # Entry point, quản lý Threads
├── config.py                # Baudrate, Interface, Mappings
├── sniffer.py               # Bắt gói tin L2-L4 bằng Scapy / libpcap
├── flow_engine.py           # Quản lý Flow Table & Cửa sổ trượt 2s / 100 host
├── quantizer.py             # Lượng tử hóa 28 features & 616-bit packing
├── uart_bridge.py           # Gửi nhận UART với FPGA (/dev/serial0)
└── web_dashboard/           # Flask / FastAPI + WebSocket Dashboard
    ├── app.py
    └── templates/index.html
```

### Module UART Bridge mẫu (`uart_bridge.py`):
```python
import serial
import time
import threading

class UARTBridge:
    def __init__(self, port="/dev/serial0", baudrate=921600):
        self.ser = serial.Serial(port, baudrate=baudrate, timeout=0.1)
        self.running = True
        self.on_result_callback = None

    def send_vector(self, payload_77b: bytes):
        assert len(payload_77b) == 77
        # Tính XOR Checksum
        chk = 0
        for b in payload_77b:
            chk ^= b
            
        frame = bytearray([0xAA, 0x55]) + bytearray(payload_77b) + bytearray([chk])
        self.ser.write(frame)

    def listen_loop(self):
        while self.running:
            if self.ser.in_waiting >= 3:
                b1 = self.ser.read(1)
                if b1 == b'\xBB':
                    b_class = self.ser.read(1)
                    b_chk = self.ser.read(1)
                    if b_class and b_chk:
                        class_id = int(b_class[0])
                        # Callback trả về kết quả
                        if self.on_result_callback:
                            self.on_result_callback(class_id)
            time.sleep(0.001)

    def start(self):
        t = threading.Thread(target=self.listen_loop, daemon=True)
        t.start()
```

---

## 7. CHECKLIST NGHIỆM THU CHO LẬP TRÌNH VIÊN

1. **Test Lượng tử hóa:** Chạy 1 vector từ `golden_vectors.csv` qua hàm `quantize()` $\rightarrow$ kết quả mã nguyên phải khớp 100%.
2. **Test Đóng gói 616-bit:** Kiểm tra hàm `pack_features_616bits()` trả ra đúng 77 bytes, giải mã từng slot 22-bit không bị lệch bit.
3. **Test Kết nối UART với FPGA:**
   * Nối chân: GPIO 14 (TX Pi) $\rightarrow$ Pin RX FPGA; GPIO 15 (RX Pi) $\leftarrow$ Pin TX FPGA; Nối chung Mass (GND).
   * Gửi 1 vector mẫu sang FPGA $\rightarrow$ FPGA phải trả lời khung `0xBB [class_id] [chk]` trong vòng $< 1\text{ ms}$.
4. **Test Live Traffic:**
   * Chạy lệnh `hping3 -S --flood` từ máy tấn công $\rightarrow$ Dashboard trên Pi phải đổi sang màu đỏ với thông báo `ALERT: NEPTUNE (DoS ATTACK)` ngay lập tức.
