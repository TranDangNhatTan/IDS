# FPGA / MCU IDS — Tài liệu kỹ thuật

## Mục tiêu

Project xây dựng IDS 40 lớp từ NSL-KDD và chuyển Decision Tree sang datapath integer trên FPGA. Toàn bộ luồng từ dữ liệu, preprocessing, training CPU, HDF5 integer, node ROM, RTL Verilog và mô phỏng Icarus được lưu dưới `ME/`.

Trạng thái hiện tại: Phase 0–8 đã hoàn tất ở mức software, artifact và RTL simulation. Theo yêu cầu, Phase 8 không chạy synthesis.

## Thứ tự đọc tài liệu

1. [Dữ liệu, ground truth và model](01_data_model.md)
2. [Pipeline software và runtime](02_software_runtime.md)
3. [Contract fixed-point và input FPGA](03_fpga_contract.md)
4. [Kiến trúc RTL tổng quan](04_rtl_roadmap.md)
5. [Triển khai Phase 0–5](05_phase_0_to_5_implementation.md)
6. [Tree evaluator IP bằng Verilog](06_rtl_tree_engine.md)
7. [Feature ingest và packet pipeline](07_feature_ingest_and_packet_pipeline.md)
8. [Mô phỏng RTL bằng Icarus](08_rtl_simulation.md)
9. [Tổng quan end-to-end software đến hardware](09_end_to_end_sw_hw.md)
10. [ACG525 RTL8211F onboard ↔ một LAN8720 ngoài](10_acg525_onboard_rtl8211f_lan8720.md)

## Cấu trúc project

```text
ME/
├── config/                       # feature/class/node/training contract
├── docs/                         # tài liệu 01–09
├── sw/
│   ├── dataset/                  # raw và ground truth
│   ├── feature_contract/         # encode/quantize integer
│   ├── train_model/              # train/tune CPU
│   ├── export_model/             # HDF5, node CSV, ROM exporter
│   ├── runtime/                  # reference evaluator thuần integer
│   ├── tests/                    # regression tests
│   └── tree/                     # model runs và metrics
└── hw/
    ├── model_export/             # ROM/schema/golden artifacts
    ├── rtl/                      # Verilog Phase 6–7
    ├── tb/                       # Icarus testbenches và vectors
    ├── scripts/                  # vector generator/simulation runner
    └── sim/                      # compile output và simulation report
```

## Model release chính

| Thuộc tính | Giá trị |
|---|---:|
| Profile | `fpga_flow28` |
| Feature | 28 integer/category/Q0.16 |
| Class | 40 |
| Depth | 20 |
| Node / leaf | 1.273 / 637 |
| Test accuracy | 95,48% |
| Test macro-F1 | 66,07% |
| Attack recall | 99,70% |
| False-positive rate | 6,30% |

Model đầy đủ 41 feature vẫn được giữ làm reference, nhưng cần L7/host telemetry và không phải artifact mặc định cho packet-only FPGA.

## Quick start trên Windows CMD

```bat
REM Python regression
.\.venv\Scripts\python.exe -m unittest discover -s ME\sw\tests -v

REM Inference thuần integer từ ROM
.\.venv\Scripts\python.exe -m ME.sw.runtime.predict_integer_tree --rom-mem ME\hw\model_export\dt_fpga_flow28_fixed\node_rom.mem --schema ME\hw\model_export\dt_fpga_flow28_fixed\fpga_input_schema.csv --input ME\hw\model_export\dt_fpga_flow28_fixed\golden_vectors.csv --output ME\hw\model_export\dt_fpga_flow28_fixed\predictions_from_mem.csv

REM Chạy toàn bộ RTL simulation, không synthesis
ME\hw\scripts\run_icarus.bat
```

Kết quả mong đợi cuối:

```text
RTL_SIMULATION_PASS tests=4 vectors=22156 synthesis=false
```

## Tài liệu bring-up phần cứng mới

11. [Nhật ký bring-up Ethernet ACG525, cấu hình hai máy và lỗi đã gặp](11_acg525_ethernet_bringup_log.md)
12. [UART debug bridge Ethernet ACG525 và bảng giải mã status](12_acg525_uart_debug.md)

Hai tài liệu này ghi lại kết quả thực nghiệm hiện tại. Sender Python đã gửi
được dữ liệu, nhưng ARP ở cả hai đầu vẫn là `Unreachable`; bridge chưa pass
end-to-end. UART debug là bước đang thực hiện để khoanh vùng lỗi phần cứng/RTL.
