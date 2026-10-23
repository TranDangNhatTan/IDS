# Evidence đo latency và thông lượng `final_sys`

## Phạm vi chứng minh

Tài liệu tách rõ ba đại lượng thường bị nhầm lẫn:

1. **Latency IP core**: từ clock cạnh lên nhận `start` và 616-bit feature đã
   có sẵn trong FPGA đến `result_valid`.
2. **Thông lượng IP core**: số record mà Decision Tree có thể xử lý nội bộ.
3. **Thông lượng end-to-end**: Pi gửi UART FEATURE đến khi Pi nhận UART RESULT.

Số liệu là kết quả mô phỏng RTL 50 MHz bằng Icarus. Chúng chưa thay thế báo
cao timing P&R trên chip; P&R phải PASS 50 MHz trước khi dùng làm số liệu phần
cứng cuối cùng.

## Cấu hình đo

| Hạng mục | Giá trị |
|---|---:|
| Clock | 50 MHz |
| Chu kỳ clock | 20 ns |
| Feature record | 28 x 22 = 616 bit = 77 byte |
| UART | 115200 8N1, `CLKS_PER_BIT=434` |
| Chu kỳ bit thực trong RTL | 434 x 20 ns = 8.68 us |
| Model thử core | leaf tại node 0 và chain 64 node |

Chạy lại phép đo:

```powershell
cd ME\fpga\final_sys
.\scripts\run_perf_tb.ps1
```

Kết quả RTL hiện tại:

```text
PERF_ENGINE_LEAF cycles=2 latency_ns=50000
PERF_ENGINE_64_NODE cycles=128 latency_ns=2570000
PERF_RESULT_UART encoded_bytes=17 latency_ns=1476690000
FINAL_SYS_PERF_TB_PASS
```

`%t` của Icarus in theo độ chính xác ps; do đó `50000` tương ứng 50 ns từ cạnh
âm dùng để bắt đầu phép đo. Từ cạnh lên thực sự lấy mẫu `start`, latency core
là 2 cycle = 40 ns. Tương tự chain 64 node là 128 cycle = 2.56 us; số đo
2.57 us bao gồm nửa cycle (10 ns) trước cạnh clock đầu tiên.

## Chứng minh latency core

FSM `ids_tree_engine_live` thực hiện hai cycle cho mỗi node đã đi qua:

```text
WAIT: đọc node hiện hành từ BRAM
EVAL: so sánh feature, chọn child hoặc phát leaf result
```

Với `N` node, từ cạnh lên nhận `start`:

```text
C_core(N) = 2N cycle
T_core(N) = 2N / 50,000,000 second
```

| Node đã đi qua | Cycle | Latency core |
|---:|---:|---:|
| 1 (root là leaf) | 2 | 40 ns |
| 3 | 6 | 120 ns |
| 32 | 64 | 1.28 us |
| 64 (giới hạn `MAX_STEPS`) | 128 | 2.56 us |

WaveDrom minh họa path 3 node nằm trong `core_latency_wavedrom.json`; VCD từ
Icarus nằm tại `../tb_perf.vcd` và có thể mở bằng GTKWave.

## Chứng minh thông lượng IP core

Core không pipeline nhiều inference cùng lúc; một record hoàn tất rồi record
kế tiếp mới launch. Do đó thông lượng worst-case là:

```text
R_core_worst = 50,000,000 / 128 = 390,625 record/s
B_core_worst = 390,625 x 616 = 240,625,000 bit/s = 240.625 Mbit/s
```

Thông lượng này là **equivalent feature bandwidth** bên trong FPGA, không phải
băng thông Ethernet. Path thực tế của model có thể ngắn hơn 64 node, nên cao
hơn; cần replay tập golden vector để công bố average record/s của model thật.

## Chứng minh giới hạn UART end-to-end

FEATURE decoded frame có 85 byte: header 6 + feature payload 77 + CRC 2.
COBS thêm một code byte và `0x00` delimiter, nên UART gửi 87 byte:

```text
T_feature_uart = 87 x 10 x 8.68 us = 7.5516 ms
```

RESULT decoded frame có 15 byte: header 6 + payload 7 + CRC 2. UART gửi 17
byte sau COBS/delimiter; Icarus đo được:

```text
T_result_uart = 1.47669 ms
```

Worst-case transaction một record đang chờ ACK:

```text
T_e2e ~= 7.5516 ms + 0.003 ms + 1.47669 ms = 9.031 ms
R_e2e ~= 1 / 9.031 ms = 110.7 record/s
B_e2e_feature ~= 110.7 x 616 = 68.2 kbit/s
```

Kết luận: core đạt tối thiểu 240.625 Mbit/s equivalent feature bandwidth,
nhưng toàn hệ thống hiện bị UART 115200 giới hạn khoảng 68.2 kbit/s feature
hữu ích hoặc 110 record/s. Đây là lý do Pi phải gom packet thành flow/window
trước khi gửi FPGA.
