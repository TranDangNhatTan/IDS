# 01 — Dữ liệu, ground truth và model

## Dataset

Nguồn raw là NSL-KDD trong `ME/sw/dataset/raw/NSL-KDD-DataSet-master/`:

- `KDDTrain+.txt`: 125.973 record.
- `KDDTest+.txt`: 22.544 record.
- Mỗi record có 41 feature, label và difficulty.
- Dataset chứa connection record đã trích feature, không phải PCAP hay Ethernet frame.

`build_ground_truth.py` gộp hai tập đầy đủ, loại duplicate nhất quán và quarantine các feature vector có label xung đột. Ground truth sạch có 147.674 record và 40 lớp. `label`, `difficulty` và provenance không được dùng làm input.

## Split

Split class-aware cố định với seed 42:

| Split | Record |
|---|---:|
| Train | 103.366 |
| Validation | 22.152 |
| Test | 22.156 |

Validation dùng để chọn hyperparameter. Sau khi chọn, model fit lại trên train+validation; test chỉ dùng để đánh giá cuối.

## Hai profile model

### `full41`

Dùng đủ 41 feature, gồm 12 content/L7 feature. Đây là reference khi SW/host telemetry cung cấp đủ dữ liệu.

| Metric | Giá trị |
|---|---:|
| Node / depth | 2.363 / 50 |
| Test accuracy | 99,34% |
| Macro-F1 | 69,50% |
| Attack recall | 99,45% |
| FPR | 0,45% |

### `fpga_flow28`

Loại content feature mà header/flow-only FPGA không thể tạo chính xác. Đây là release profile dùng cho RTL.

| Metric | Giá trị |
|---|---:|
| Node / depth | 1.273 / 20 |
| Test accuracy | 95,48% |
| Macro-F1 | 66,07% |
| Attack recall | 99,70% |
| FPR | 6,30% |

FPR của flow-only còn cao; đây là giới hạn model cần tiếp tục tối ưu, không phải lỗi fixed-point hay RTL.

## Artifact model

```text
ME/sw/tree/dt_fpga_flow28_fixed/
├── pipeline.joblib          # sklearn offline oracle
├── model_integer.h5         # deployment model integer
├── category_codes.json
├── class_map.json
├── selection_metrics.csv
├── test_predictions.csv
└── run_metadata.json
```

Decision Tree không có weight matrix. “Weight” triển khai của model là bảng node: operation, feature ID, integer threshold, child pointers và class ID.
