# SPEC KỸ THUẬT: TIỀN XỬ LÝ DỮ LIỆU IDS TRÊN ESP32-P4 VÀ GIAO TIẾP SPI VỚI FPGA

> **Tài liệu bàn giao cho Agent / Lập trình viên Firmware ESP32-P4 & RTL FPGA**  
> Dự án: FPGA-based Network Intrusion Detection System (NSL-KDD `fpga_flow28`)  
> Mục tiêu: Tách tải toàn bộ khâu bóc tách gói tin (Packet Parsing), theo dõi luồng (Flow Tracking) và lượng tử hóa (Quantization) từ FPGA sang vi điều khiển **ESP32-P4**; truyền vector đặc trưng 616-bit (77 bytes) qua **SPI** sang FPGA chạy **Decision Tree Engine**.

---

## 1. TỔNG QUAN KIẾN TRÚC HỆ THỐNG

### 1.1 Sơ đồ khối tổng thể
```
LAN1 (10 Mbps In) ──> [ESP32-P4: EMAC + LAN8720]
                            │
                            ├─► [Core 0: Network Ingest & Packet Parser]
                            │         │
                            │         ▼
                            │   [Flow Table & Sliding Window Engine]
                            │         │
                            │         ▼ (28 Raw Features)
                            ├─► [Core 1: Quantization & 616-bit Packing]
                            │         │
                            │         ▼ SPI Master DMA (20 MHz, Mode 0)
                            │   [SPI Bus: MOSI, SCLK, CS#]
                            │         │
                            │         ▼
                      [FPGA ACG525: SPI Slave Receiver]
                            │
                            ▼ 616-bit Feature Snapshot
                      [ids_tree_engine (1.273 nodes)]
                            │
                            ▼ Class ID (0..39)
                      [UART TX: 115200 / 921600 baud] ──> Laptop Web Dashboard
```

### 1.2 Phân định trách nhiệm (Contract Separation)
* **ESP32-P4:** 
  1. Nhận Ethernet frame từ LAN1.
  2. Bóc tách header IPv4, TCP/UDP.
  3. Cập nhật bảng kết nối (Flow Table) và cửa sổ trượt (Time & Host Window).
  4. Lượng tử hóa 28 đặc trưng theo quy chuẩn số nguyên (`fpga_flow28`).
  5. Đóng gói 28 giá trị (mỗi giá trị 22-bit zero-extended) thành khối **77 bytes** (616 bits).
  6. Truyền 77 bytes qua SPI Master sang FPGA.
* **FPGA (Gowin GW5A-25B / ACG525):**
  1. SPI Slave nhận 77 bytes vào thanh ghi `feature_snapshot[615:0]`.
  2. Kích hoạt `ids_tree_engine` chạy duyệt 1 cây quyết định (1.273 nodes trong Block RAM ROM).
  3. Trả về `class_id` (0..39) ra UART để hiển thị web dashboard.

---

## 2. QUY CHUẨN 28 ĐẶC TRƯNG (`fpga_flow28` PROFILE)

Mỗi vector gồm đúng **28 đặc trưng**, sắp xếp theo đúng thứ tự ID từ **0 đến 27**.  
Trong thanh ghi phần cứng của FPGA, mỗi đặc trưng chiếm một slot **22-bit** (zero-extended). Tổng độ rộng: $28 \times 22 = 616\text{ bits}$.

### Bảng chi tiết 28 Đặc trưng:

| ID | Tên Đặc Trưng | Phân Loại | Bit Width Tự Nhiên | Quy Tắc Tính Toán / Lượng Tử Hóa | Bão Hòa (Saturate At) |
|:--:|:---|:---:|:---:|:---|:---:|
| **0** | `duration` | Integer | 15 bit | $\min(\text{raw\_duration}, 16744)$ | 16.744 |
| **1** | `protocol_type` | Categorical | 2 bit | Tra bảng: `icmp`=1, `tcp`=2, `udp`=3 (Unknown=0) | 3 |
| **2** | `service` | Categorical | 7 bit | Tra bảng 70 dịch vụ (1..70, Unknown=0) | 70 |
| **3** | `flag` | Categorical | 4 bit | Tra bảng 11 trạng thái cờ (1..11, Unknown=0) | 11 |
| **4** | `src_bytes` | Integer | 18 bit | $\min(\text{raw\_src\_bytes} \gg 2,\, 240748)$ *(chia 4)* | 240.748 |
| **5** | `dst_bytes` | Integer | 12 bit | $\min(\text{raw\_dst\_bytes} \gg 6,\, 3309)$ *(chia 64)* | 3.309 |
| **6** | `land` | Boolean | 1 bit | $1$ nếu $(\text{src\_ip} == \text{dst\_ip} \ \&\&\ \text{src\_port} == \text{dst\_port})$, ngược lại $0$ | 1 |
| **7** | `wrong_fragment` | Integer | 2 bit | $\min(\text{raw\_wrong\_fragment}, 3)$ | 3 |
| **8** | `urgent` | Integer | 1 bit | $\min(\text{raw\_urgent\_packets}, 1)$ | 1 |
| **9** | `count` | Integer | 9 bit | $\min(\text{connections\_to\_same\_dst\_last\_2s}, 511)$ | 511 |
| **10** | `srv_count` | Integer | 7 bit | $\min(\text{connections\_to\_same\_srv\_last\_2s}, 100)$ | 100 |
| **11** | `serror_rate` | Rate (Q0.16) | 16 bit | $\text{round}(\text{clamp}(v, 0, 1) \times 65535)$ | 65.535 |
| **12** | `srv_serror_rate` | Rate (Q0.16) | 16 bit | $\text{round}(\text{clamp}(v, 0, 1) \times 65535)$ | 65.535 |
| **13** | `rerror_rate` | Rate (Q0.16) | 16 bit | $\text{round}(\text{clamp}(v, 0, 1) \times 65535)$ | 65.535 |
| **14** | `srv_rerror_rate` | Rate (Q0.16) | 16 bit | $\text{round}(\text{clamp}(v, 0, 1) \times 65535)$ | 65.535 |
| **15** | `same_srv_rate` | Rate (Q0.16) | 16 bit | $\text{round}(\text{clamp}(v, 0, 1) \times 65535)$ | 65.535 |
| **16** | `diff_srv_rate` | Rate (Q0.16) | 16 bit | $\text{round}(\text{clamp}(v, 0, 1) \times 65535)$ | 65.535 |
| **17** | `srv_diff_host_rate` | Rate (Q0.16) | 16 bit | $\text{round}(\text{clamp}(v, 0, 1) \times 65535)$ | 65.535 |
| **18** | `dst_host_count` | Integer | 8 bit | $\min(\text{connections\_to\_dst\_last\_100}, 253)$ | 253 |
| **19** | `dst_host_srv_count` | Integer | 8 bit | $\min(\text{connections\_to\_srv\_last\_100}, 255)$ | 255 |
| **20** | `dst_host_same_srv_rate` | Rate (Q0.16) | 16 bit | $\text{round}(\text{clamp}(v, 0, 1) \times 65535)$ | 65.535 |
| **21** | `dst_host_diff_srv_rate` | Rate (Q0.16) | 16 bit | $\text{round}(\text{clamp}(v, 0, 1) \times 65535)$ | 65.535 |
| **22** | `dst_host_same_src_port_rate` | Rate (Q0.16) | 16 bit | $\text{round}(\text{clamp}(v, 0, 1) \times 65535)$ | 65.535 |
| **23** | `dst_host_srv_diff_host_rate` | Rate (Q0.16) | 16 bit | $\text{round}(\text{clamp}(v, 0, 1) \times 65535)$ | 65.535 |
| **24** | `dst_host_serror_rate` | Rate (Q0.16) | 16 bit | $\text{round}(\text{clamp}(v, 0, 1) \times 65535)$ | 65.535 |
| **25** | `dst_host_srv_serror_rate` | Rate (Q0.16) | 16 bit | $\text{round}(\text{clamp}(v, 0, 1) \times 65535)$ | 65.535 |
| **26** | `dst_host_rerror_rate` | Rate (Q0.16) | 16 bit | $\text{round}(\text{clamp}(v, 0, 1) \times 65535)$ | 65.535 |
| **27** | `dst_host_srv_rerror_rate` | Rate (Q0.16) | 16 bit | $\text{round}(\text{clamp}(v, 0, 1) \times 65535)$ | 65.535 |

---

## 3. BẢNG TRA CỨU CATEGORICAL (LOOKUP TABLES)

Bắt buộc tra cứu ra đúng mã nguyên (1-based, mã `0` dành riêng cho Unknown):

### 3.1 `protocol_type` (ID = 1)
```c
static inline uint8_t encode_protocol(uint8_t ip_proto) {
    switch (ip_proto) {
        case 1:  return 1; // ICMP
        case 6:  return 2; // TCP
        case 17: return 3; // UDP
        default: return 0; // Unknown
    }
}
```

### 3.2 `flag` (ID = 3)
| Tên Cờ | Mã Code | Ý Nghĩa Trạng Thái Kết Nối TCP |
|:---|:---:|:---|
| `OTH` | 1 | Giao thức khác / trạng thái chuyển tiếp |
| `REJ` | 2 | Kết nối bị từ chối (nhận RST) |
| `RSTO` | 3 | Kết nối bị reset từ phía Originator |
| `RSTOS0` | 4 | Gửi SYN rồi nhận RST |
| `RSTR` | 5 | Kết nối bị reset từ phía Responder |
| `S0` | 6 | Đã gửi SYN, không nhận được phản hồi (SYN flood) |
| `S1` | 7 | Đã bắt tay 3 bước, chưa có trao đổi dữ liệu |
| `S2` | 8 | Đã kết nối, 1 bên đóng nhưng bên kia không đóng |
| `S3` | 9 | Đã kết nối, đóng bình thường 1 chiều |
| `SF` | 10 | Kết nối thành công và đóng hoàn chỉnh (SYN-FIN) |
| `SH` | 11 | Chỉ gửi SYN và FIN (không có dữ liệu) |

### 3.3 `service` (ID = 2) - Bảng 70 Port/Dịch Vụ Phổ Biến
Map port đích TCP/UDP sang mã code:
```c
// Mapping cơ bản các port phổ biến:
// port 80   -> http (25)
// port 443  -> http_443 (27)
// port 21   -> ftp (20)
// port 20   -> ftp_data (21)
// port 22   -> ssh (57)
// port 23   -> telnet (61)
// port 25   -> smtp (55)
// port 53   -> domain_u (13) / domain (12)
// port 110  -> pop_3 (48)
// port 123  -> ntp_u (44)
// port 143  -> imap4 (29)
// port 161  -> snmpgetattack / snmpguess
// Các port khác -> other (45) hoặc private (50)
```
*(Chi tiết đủ 70 tên service nằm trong file `ME/hw/model_export/dt_fpga_flow28_fixed/fpga_category_codes.csv`).*

---

## 4. QUY CÁCH ĐÓNG GÓI BIT (BIT-PACKING) CHO BUS SPI

### 4.1 Quy cách thanh ghi trên FPGA
* Thanh ghi nhận diện trên FPGA có kích thước: **616 bits** ($[615:0]$).
* Mỗi đặc trưng $i \in [0..27]$ chiếm 22 bit:
  $$\text{bit\_range}(i) = [i \times 22 + 21 \;:\; i \times 22]$$
  * Đặc trưng 0 (`duration`): bits $[21:0]$
  * Đặc trưng 1 (`protocol_type`): bits $[43:22]$
  * ...
  * Đặc trưng 27 (`dst_host_srv_rerror_rate`): bits $[615:594]$

### 4.2 Thuật toán đóng gói (Packing Function C cho ESP32-P4)
Vì 616 bits = đúng 77 bytes ($616 / 8 = 77$), dữ liệu được nhồi liên tục dạng Little-Endian Bit-stream:

```c
#include <stdint.h>
#include <string.h>

typedef struct {
    uint32_t val[28]; // Mỗi giá trị đã qua lượng tử hóa
} feature_vector_t;

void pack_features_616bits(const feature_vector_t *features, uint8_t *out_bytes_77) {
    memset(out_bytes_77, 0, 77);
    uint32_t global_bit_offset = 0;

    for (int i = 0; i < 28; i++) {
        uint32_t f_val = features->val[i] & 0x003FFFFF; // Mask đúng 22-bit

        for (int b = 0; b < 22; b++) {
            if (f_val & (1UL << b)) {
                uint32_t bit_idx = global_bit_offset + b;
                out_bytes_77[bit_idx / 8] |= (1 << (bit_idx % 8));
            }
        }
        global_bit_offset += 22;
    }
}
```

---

## 5. THIẾT KẾ GIAO TIẾP VẬT LÝ SPI (ESP32-P4 ↔ FPGA)

### 5.1 Cấu hình SPI Physical Interface
* **Vai trò:**
  * ESP32-P4: **SPI Master**
  * FPGA (ACG525): **SPI Slave**
* **Số dây (4 dây):**
  1. `SCLK`: Xung nhịp (Clock: **20 MHz**, có thể nâng lên 40 MHz).
  2. `MOSI`: Master Out Slave In (Truyền 77 bytes từ ESP sang FPGA).
  3. `MISO`: Master In Slave Out (Tùy chọn: FPGA trả class_id hoặc trạng thái).
  4. `CS#`: Chip Select (Active Low - tích cực mức thấp).
  5. `GND`: Nối chung Mass bắt buộc giữa 2 bo mạch.
* **Chế độ SPI:** **SPI Mode 0** ($\text{CPOL} = 0, \text{CPHA} = 0$).

### 5.2 Khung truyền SPI (SPI Transaction Protocol)
Để đảm bảo chống nhiễu và dễ đồng bộ FSM trên FPGA, khuyến nghị dùng khung **80 Bytes**:

```
┌──────────────┬───────────────────────────────┬────────────┐
│ Header (2B)  │  Payload Đặc Trưng (77 Bytes) │  CRC8 (1B) │
│   0xAA, 0x55 │      616-bit Feature Vector   │  Checksum  │
└──────────────┴───────────────────────────────┴────────────┘
```

* Chu kỳ thực hiện:
  1. ESP32 kéo `CS# = 0`.
  2. Đẩy 80 bytes (hoặc 77 bytes thuần) qua SPI DMA. (Ở 20 MHz, tốn: $80 \times 8 / 20\text{MHz} = 32\ \mu\text{s}$).
  3. ESP32 kéo `CS# = 1`.
  4. Cạnh lên của `CS#` trên FPGA đóng vai trò xung **`vector_valid`**, kích hoạt FSM nạp 616 bits vào `ids_tree_engine` và bắt đầu duyệt cây.

---

## 6. KHUNG CODE MẪU TRÊN ESP-IDF (ESP32-P4)

### 6.1 Khởi tạo SPI Master DMA
```c
#include "driver/spi_master.h"
#include "esp_log.h"

#define PIN_NUM_MISO 12
#define PIN_NUM_MOSI 11
#define PIN_NUM_CLK  13
#define PIN_NUM_CS   10

static spi_device_handle_t spi_fpga_handle;

void spi_fpga_init(void) {
    spi_bus_config_t buscfg = {
        .miso_io_num = PIN_NUM_MISO,
        .mosi_io_num = PIN_NUM_MOSI,
        .sclk_io_num = PIN_NUM_CLK,
        .quadwp_io_num = -1,
        .quadhd_io_num = -1,
        .max_transfer_sz = 128
    };
    ESP_ERROR_CHECK(spi_bus_initialize(SPI2_HOST, &buscfg, SPI_DMA_CH_AUTO));

    spi_device_interface_config_t devcfg = {
        .clock_speed_hz = 20 * 1000 * 1000, // 20 MHz
        .mode = 0,                          // Mode 0
        .spics_io_num = PIN_NUM_CS,
        .queue_size = 4,
    };
    ESP_ERROR_CHECK(spi_bus_add_device(SPI2_HOST, &devcfg, &spi_fpga_handle));
}

void spi_fpga_send_vector(const uint8_t *payload_77b) {
    spi_transaction_t t = {
        .length = 77 * 8, // 616 bits
        .tx_buffer = payload_77b,
    };
    ESP_ERROR_CHECK(spi_device_transmit(spi_fpga_handle, &t));
}
```

---

## 7. ĐẶC TẢ MODULE SPI SLAVE TRÊN VERILOG (FPGA SIDE)

Code RTL trên FPGA cần 1 module nhận SPI và xuất ra bus 616-bit:

```verilog
module spi_slave_feature_receiver (
    input  wire        sys_clk,         // Clock hệ thống (50 MHz)
    input  wire        sys_rst_n,
    // Giao diện vật lý SPI từ ESP32
    input  wire        spi_sclk,
    input  wire        spi_cs_n,
    input  wire        spi_mosi,
    // Giao diện sang ids_tree_engine
    output reg [615:0] feature_snapshot,
    output reg         snapshot_valid
);

    // Đồng bộ tín hiệu SPI vào miền clock hệ thống (CDC)
    reg [2:0] sclk_sync, cs_sync, mosi_sync;
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            sclk_sync <= 3'b000;
            cs_sync   <= 3'b111;
            mosi_sync <= 3'b000;
        end else begin
            sclk_sync <= {sclk_sync[1:0], spi_sclk};
            cs_sync   <= {cs_sync[1:0], spi_cs_n};
            mosi_sync <= {mosi_sync[1:0], spi_mosi};
        end
    end

    wire sclk_rising = (sclk_sync[2:1] == 2'b01);
    wire cs_active   = ~cs_sync[1];
    wire cs_rising   = (cs_sync[2:1] == 2'b01);

    reg [615:0] shift_reg;
    reg [9:0]   bit_cnt;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            shift_reg        <= 616'd0;
            bit_cnt          <= 10'd0;
            feature_snapshot <= 616'd0;
            snapshot_valid   <= 1'b0;
        end else begin
            snapshot_valid <= 1'b0;

            if (!cs_active) begin
                bit_cnt <= 10'd0;
                if (cs_rising && (bit_cnt >= 616)) begin
                    feature_snapshot <= shift_reg;
                    snapshot_valid   <= 1'b1; // Kích hoạt chạy Decision Tree
                end
            end else if (sclk_rising) begin
                shift_reg[bit_cnt] <= mosi_sync[1]; // Shift bit vào thanh ghi
                bit_cnt <= bit_cnt + 1'b1;
            end
        end
    end

endmodule
```

---

## 8. TIÊU CHUẨN KIỂM THỬ ĐỘ TƯƠNG ĐỒNG (VERIFICATION PARITY)

Khi viết code xong, Agent/Lập trình viên cần kiểm tra tính tương đương:
1. Nạp **22.156 vector mẫu** từ file `ME/hw/model_export/dt_fpga_flow28_fixed/golden_vectors.csv` vào ESP32-P4.
2. Cho ESP32-P4 đóng gói và đẩy qua SPI sang FPGA.
3. Class ID mà FPGA trả ra qua UART **phải khớp 100%** với kết quả `golden_paths.csv` và oracle mô phỏng Python của dự án.
