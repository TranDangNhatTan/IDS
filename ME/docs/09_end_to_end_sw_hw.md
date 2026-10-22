# Tổng quan end-to-end từ software đến hardware

## Luồng artifact

```text
NSL-KDD ground truth
  → ME.sw.feature_contract: validate + integer/Q0.16 encode
  → train_hardware_tree.py: train/tune Decision Tree trên integer representation
  → pipeline.joblib: offline audit model
  → model_integer.h5: integer deployment model
  → export_hardware_model.py
      ├── fpga_tree_nodes.csv
      ├── node_rom.mem/.hex/.coe/.mif
      ├── fpga_input_schema.csv
      └── golden_vectors.csv
  → Verilog RTL
      ├── feature ingest/quantizer
      ├── synchronous node ROM
      └── tree traversal FSM
  → Icarus testbench
```

## Nguồn sự thật theo lớp

| Lớp | File chuẩn |
|---|---|
| Feature order/scale | `ME/config/feature_profile_fpga_flow.json` và `fpga_input_schema.csv` |
| Class ID | `ME/config/class_map.json` |
| Node layout | `ME/config/node_format.json` |
| Deployment model | `ME/sw/tree/dt_fpga_flow28_fixed/model_integer.h5` |
| Human-readable tree | `fpga_tree_nodes.csv` |
| FPGA ROM | `node_rom.mem` |
| RTL oracle | `golden_vectors.csv`, `golden_paths.csv` |
| Simulation report | `ME/hw/sim/results/simulation_report.json` |

## Các mức parity

Đã chứng minh trên 147.674 record:

```text
sklearn offline model = integer HDF5 = node CSV evaluator = packed ROM evaluator
```

Đã chứng minh trên toàn bộ 22.156 RTL golden vectors:

```text
packed ROM Python evaluator = Verilog tree engine = Verilog feature-to-tree top
```

Packet-to-tree test chứng minh wiring và control flow, nhưng chưa chứng minh feature semantics tương đương NSL-KDD do dataset không có PCAP.

## Các lệnh chính

Train CPU:

```bat
.\.venv\Scripts\python.exe -m ME.sw.train_model.train_hardware_tree --profile fpga_flow28 --backend cpu
```

Export HDF5 sang artifact FPGA:

```bat
.\.venv\Scripts\python.exe -m ME.sw.export_model.export_hardware_model --model-dir ME\sw\tree\dt_fpga_flow28_fixed --output-dir ME\hw\model_export\dt_fpga_flow28_fixed
```

Reference inference thuần integer:

```bat
.\.venv\Scripts\python.exe -m ME.sw.runtime.predict_integer_tree --rom-mem ME\hw\model_export\dt_fpga_flow28_fixed\node_rom.mem --schema ME\hw\model_export\dt_fpga_flow28_fixed\fpga_input_schema.csv --input ME\hw\model_export\dt_fpga_flow28_fixed\golden_vectors.csv --output ME\hw\model_export\dt_fpga_flow28_fixed\predictions_from_mem.csv
```

RTL simulation:

```bat
ME\hw\scripts\run_icarus.bat
```

## Trạng thái phase

| Phase | Trạng thái |
|---|---|
| 0 — Contract | PASS |
| 1 — Integer preprocessing | PASS |
| 2 — Hardware-aware CPU training | PASS |
| 3 — HDF5 → node CSV | PASS |
| 4 — CSV → ROM image | PASS |
| 5 — Python integer/golden parity | PASS |
| 6 — Verilog tree evaluator | PASS simulation |
| 7 — Feature ingest + packet reference integration | PASS simulation, có giới hạn semantic đã ghi ở tài liệu 07 |
| 8 — Icarus RTL simulation | PASS; synthesis không chạy theo yêu cầu |

## Việc chưa nằm trong Phase 8

- Synthesis, place-and-route, timing closure và resource utilization.
- Multi-entry production flow table/hazard handling.
- CDC với Ethernet MAC clock.
- VLAN/IPv6 parser.
- Đối chiếu packet-to-feature với PCAP/telemetry ground truth.
