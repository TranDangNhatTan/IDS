# SPEC KỸ THUẬT: TIỀN XỬ LÝ DỮ LIỆU IDS TRÊN ESP32-P4 VÀ GIAO TIẾP UART VỚI FPGA

> **Tài liệu bàn giao cho Agent / Lập trình viên Firmware ESP32-P4 & RTL FPGA**  
> Dự án: FPGA-based Network Intrusion Detection System (NSL-KDD `fpga_flow28`)  
> Mục tiêu: Tách tải toàn bộ khâu bóc tách gói tin (Packet Parsing), theo dõi luồng (Flow Tracking) và lượng tử hóa (Quantization) từ FPGA sang vi điều khiển **ESP32-P4**; truyền vector đặc trưng 616-bit (77 bytes) qua giao tiếp **UART tốc độ cao (High-Speed UART)** sang FPGA chạy **Decision Tree Engine**.

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
                            │         ▼ UART TX (921.600 baud / 2.000.000 baud)
                            │   [Chân UART: TX_ESP ──> RX_FPGA] (Chung GND)
                            │         │
                            │         ▼
                      [FPGA ACG525: UART RX Receiver + Frame Parser]
                            │
                            ▼ 616-bit Feature Snapshot
                      [ids_tree_engine (1.273 nodes)]
                            │
                            ▼ Class ID (0..39)
                      [UART TX: 115200 / 921600 baud] ──> Laptop Web Dashboard
```

### 1.2 Phân định trách nhiệm
* **ESP32-P4:** 
  1. Nhận Ethernet frame từ LAN1.
  2. Bóc tách header IPv4, TCP/UDP.
  3. Cập nhật bảng kết nối (Flow Table) và cửa sổ trượt (Time & Host Window).
  4. Lượng tử hóa 28 đặc trưng theo quy chuẩn số nguyên (`fpga_flow28`).
  5. Đóng gói 28 giá trị (mỗi giá trị 22-bit zero-extended) thành khối **77 bytes** (616 bits).
  6. Ghép khung UART (Header 2B + Payload 77B + Checksum 1B = **80 Bytes**) và phát qua UART TX.
* **FPGA (Gowin GW5A-25B / ACG525):**
  1. UART RX nhận luồng byte, FSM tìm header `0xAA, 0x55`, gom đủ 77 bytes và kiểm tra Checksum.
  2. Nạp 616-bit vào thanh ghi `feature_snapshot[615:0]`.
  3. Kích hoạt `ids_tree_engine` chạy duyệt 1 cây quyết định (1.273 nodes trong Block RAM ROM).
  4. Trả về `class_id` (0..39) ra cổng UART nối Laptop để hiển thị web dashboard.

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

## 4. QUY CÁCH ĐÓNG GÓI BIT (BIT-PACKING) 616-BIT

### 4.1 Quy cách thanh ghi trên FPGA
* Thanh ghi nhận diện trên FPGA có kích thước: **616 bits** ($[615:0]$).
* Mỗi đặc trưng $i \in [0..27]$ chiếm 22 bit:
  $$\text{bit\_range}(i) = [i \times 22 + 21 \;:\; i \times 22]$$
  * Đặc trưng 0 (`duration`): bits $[21:0]$
  * Đặc trưng 1 (`protocol_type`): bits $[43:22]$
  * ...
  * Đặc trưng 27 (`dst_host_srv_rerror_rate`): bits $[615:594]$

### 4.2 Thuật toán đóng gói (Packing Function C cho ESP32-P4)
Đóng gói 28 giá trị này thành mảng **77 bytes** ($616 / 8 = 77$) dạng Little-Endian Bit-stream:

```c
#include <stdint.h>
#include <string.h>

typedef struct {
    uint32_t val[28]; // Mỗi giá trị đã qua lượng tử hóa
} feature_vector_t;

void pack_features_616bits(const feature_vector_t *features, uint8_t *out_payload_77) {
    memset(out_payload_77, 0, 77);
    uint32_t global_bit_offset = 0;

    for (int i = 0; i < 28; i++) {
        uint32_t f_val = features->val[i] & 0x003FFFFF; // Mask đúng 22-bit

        for (int b = 0; b < 22; b++) {
            if (f_val & (1UL << b)) {
                uint32_t bit_idx = global_bit_offset + b;
                out_payload_77[bit_idx / 8] |= (1 << (bit_idx % 8));
            }
        }
        global_bit_offset += 22;
    }
}
```

---

## 5. THIẾT KẾ GIAO THỨC TRUYỀN UART (ESP32-P4 ↔ FPGA)

### 5.1 Cấu hình tham số UART
* **Đường truyền vật lý (2 dây):**
  1. `TX_ESP` nối `RX_FPGA` (truyền vector sang FPGA).
  2. `GND` nối chung giữa 2 bo mạch.
  3. *(Tùy chọn)*: `TX_FPGA` nối `RX_ESP` nếu muốn FPGA gửi phản hồi class_id về ESP32.
* **Tốc độ Baud:** Khuyến nghị **`921.600 baud`** hoặc **`2.000.000 baud`** (High-Speed UART).
  * Tại **921.600 baud**: 1 byte = 10 bit (1 start + 8 data + 1 stop). Tốc độ truyền: $92.160\text{ bytes/giây} \approx 1.152\text{ vector/giây}$ (thừa sức đáp ứng traffic thông thường ở 10 Mbps).
  * Tại **2.000.000 baud**: Truyền 1 vector 80 bytes chỉ mất đúng **$400\ \mu\text{s}$**.
* **Định dạng khung:** `8-N-1` (8 data bits, No parity, 1 stop bit).

### 5.2 Cấu trúc Khung Tin UART (UART Frame Protocol - 80 Bytes)
Để FPGA dễ dàng nhận diện điểm đầu gói tin và chống trôi dữ liệu khi có nhiễu, bắt buộc bọc 77 bytes payload vào khung cố định **80 Bytes**:

```
┌──────────────┬──────────────┬───────────────────────────────┬────────────┐
│ Byte 0       │ Byte 1       │ Bytes 2 .. 78                 │ Byte 79    │
│ Sync Byte 1  │ Sync Byte 2  │ Payload Đặc Trưng (77 Bytes)  │ Checksum   │
│ 0xAA         │ 0x55         │ 616-bit Packed Vector         │ XOR / Sum  │
└──────────────┴──────────────┴───────────────────────────────┴────────────┘
```

* **Quy tắc Checksum:**
  XOR của tất cả 77 bytes dữ liệu:
  $$\text{Checksum} = \text{payload}[0] \oplus \text{payload}[1] \oplus \dots \oplus \text{payload}[76]$$

---

## 6. KHUNG CODE MẪU TRÊN ESP-IDF (ESP32-P4)

### 6.1 Khởi tạo UART Driver và Gửi Khung 80 Bytes
```c
#include "driver/uart.h"
#include "esp_log.h"
#include <string.h>

#define UART_PORT_NUM      UART_NUM_1
#define UART_BAUD_RATE     921600   // Có thể đổi thành 2000000 (2M baud)
#define TX_PIN_NUM         11       // Chân GPIO TX nối sang FPGA
#define RX_PIN_NUM         12       // Chân GPIO RX

void uart_fpga_init(void) {
    const uart_config_t uart_config = {
        .baud_rate = UART_BAUD_RATE,
        .data_bits = UART_DATA_8_BITS,
        .parity    = UART_PARITY_DISABLE,
        .stop_bits = UART_STOP_BITS_1,
        .flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
        .source_clk = UART_SCLK_DEFAULT,
    };
    ESP_ERROR_CHECK(uart_driver_install(UART_PORT_NUM, 1024, 0, 0, NULL, 0));
    ESP_ERROR_CHECK(uart_param_config(UART_PORT_NUM, &uart_config));
    ESP_ERROR_CHECK(uart_set_pin(UART_PORT_NUM, TX_PIN_NUM, RX_PIN_NUM, UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE));
}

// Hàm gửi khung 80-byte hoàn chỉnh sang FPGA
void uart_fpga_send_vector(const uint8_t *payload_77b) {
    uint8_t frame[80];
    frame[0] = 0xAA; // Sync 1
    frame[1] = 0x55; // Sync 2
    
    memcpy(&frame[2], payload_77b, 77);

    // Tính XOR Checksum
    uint8_t chk = 0;
    for (int i = 0; i < 77; i++) {
        chk ^= payload_77b[i];
    }
    frame[79] = chk;

    // Gửi qua UART
    uart_write_bytes(UART_PORT_NUM, (const char *)frame, 80);
}
```

---

## 7. ĐẶC TẢ MODULE UART RECEIVER TRÊN VERILOG (FPGA SIDE)

Module Verilog này nhận byte stream từ chân RX của ESP32, kiểm tra Header `0xAA, 0x55`, gom 77 bytes, kiểm tra Checksum, và xuất ra bus **616-bit** để kích hoạt `ids_tree_engine`:

```verilog
module uart_feature_receiver (
    input  wire        sys_clk,         // Clock hệ thống FPGA (50 MHz)
    input  wire        sys_rst_n,
    input  wire        uart_rx_pin,     // Tín hiệu RX từ ESP32-P4
    output reg [615:0] feature_snapshot,// 616 bits đưa sang ids_tree_engine
    output reg         snapshot_valid   // Xung kích hoạt chạy cây quyết định
);

    parameter CLK_FREQ  = 50_000_000;
    parameter BAUD_RATE = 921_600;      // Khớp với baud rate trên ESP32
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

    // -------------------------------------------------------------
    // 1. Bộ giải mã UART RX cơ bản (Byte Deserializer)
    // -------------------------------------------------------------
    reg [2:0] rx_sync;
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) rx_sync <= 3'b111;
        else rx_sync <= {rx_sync[1:0], uart_rx_pin};
    end
    wire rx_bit = rx_sync[2];

    reg [1:0]  rx_state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  rx_byte_reg;
    reg        rx_byte_valid;

    localparam S_IDLE  = 2'd0, S_START = 2'd1, S_DATA  = 2'd2, S_STOP  = 2'd3;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            rx_state      <= S_IDLE;
            clk_cnt       <= 16'd0;
            bit_idx       <= 3'd0;
            rx_byte_reg   <= 8'd0;
            rx_byte_valid <= 1'b0;
        end else begin
            rx_byte_valid <= 1'b0;
            case (rx_state)
                S_IDLE: begin
                    clk_cnt <= 16'd0;
                    bit_idx <= 3'd0;
                    if (rx_bit == 1'b0) rx_state <= S_START;
                end
                S_START: begin
                    if (clk_cnt == (CLKS_PER_BIT / 2)) begin
                        if (rx_bit == 1'b0) begin
                            clk_cnt  <= 16'd0;
                            rx_state <= S_DATA;
                        end else rx_state <= S_IDLE;
                    end else clk_cnt <= clk_cnt + 1'b1;
                end
                S_DATA: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 16'd0;
                        rx_byte_reg[bit_idx] <= rx_bit;
                        if (bit_idx == 3'd7) rx_state <= S_STOP;
                        else bit_idx <= bit_idx + 1'b1;
                    end else clk_cnt <= clk_cnt + 1'b1;
                end
                S_STOP: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt       <= 16'd0;
                        rx_byte_valid <= 1'b1; // Nhận thành công 1 byte
                        rx_state      <= S_IDLE;
                    end else clk_cnt <= clk_cnt + 1'b1;
                end
            endcase
        end
    end

    // -------------------------------------------------------------
    // 2. FSM Bóc tách Khung 80-byte (Sync Header 0xAA55 -> 77B -> Checksum)
    // -------------------------------------------------------------
    localparam F_SYNC1   = 2'd0;
    localparam F_SYNC2   = 2'd1;
    localparam F_PAYLOAD = 2'd2;
    localparam F_CHECK   = 2'd3;

    reg [1:0]  frame_state;
    reg [6:0]  byte_cnt;
    reg [7:0]  checksum_calc;
    reg [7:0]  payload_buffer [0:76];

    integer i;

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            frame_state      <= F_SYNC1;
            byte_cnt         <= 7'd0;
            checksum_calc    <= 8'd0;
            feature_snapshot <= 616'd0;
            snapshot_valid   <= 1'b0;
        end else begin
            snapshot_valid <= 1'b0;

            if (rx_byte_valid) begin
                case (frame_state)
                    F_SYNC1: begin
                        if (rx_byte_reg == 8'hAA) frame_state <= F_SYNC2;
                    end
                    F_SYNC2: begin
                        if (rx_byte_reg == 8'h55) begin
                            frame_state   <= F_PAYLOAD;
                            byte_cnt      <= 7'd0;
                            checksum_calc <= 8'd0;
                        end else begin
                            frame_state <= F_SYNC1;
                        end
                    end
                    F_PAYLOAD: begin
                        payload_buffer[byte_cnt] <= rx_byte_reg;
                        checksum_calc <= checksum_calc ^ rx_byte_reg;
                        if (byte_cnt == 7'd76) begin
                            frame_state <= F_CHECK;
                        end else begin
                            byte_cnt <= byte_cnt + 1'b1;
                        end
                    end
                    F_CHECK: begin
                        if (rx_byte_reg == checksum_calc) begin
                            // Đổi mảng 77 byte thành thanh ghi 616-bit
                            for (i = 0; i < 77; i = i + 1) begin
                                feature_snapshot[i*8 +: 8] <= payload_buffer[i];
                            end
                            snapshot_valid <= 1'b1; // Báo hiệu cho Tree Engine chạy
                        end
                        frame_state <= F_SYNC1;
                    end
                endcase
            end
        end
    end

endmodule
```

---

## 8. TIÊU CHUẨN KIỂM THỬ ĐỘ TƯƠNG ĐỒNG (VERIFICATION PARITY)

Khi viết code xong, Agent/Lập trình viên cần kiểm tra tính tương đương:
1. Lấy dữ liệu mẫu từ file `ME/hw/model_export/dt_fpga_flow28_fixed/golden_vectors.csv` (22.156 vectors).
2. Cho ESP32-P4 phát lần lượt các vector qua cổng UART nối sang FPGA.
3. Class ID mà FPGA in ra cổng UART debug **phải khớp 100%** với kết quả `golden_paths.csv` và oracle mô phỏng Python của dự án.
